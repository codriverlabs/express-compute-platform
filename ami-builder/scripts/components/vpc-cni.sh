#!/bin/bash
set -e
source /tmp/ami-build.env
MANIFESTS_DIR="/opt/eks-d/manifests"

echo "  Downloading VPC CNI manifest (v1.20.4)..."
sudo mkdir -p "${MANIFESTS_DIR}"
sudo curl -sL \
  "https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v1.20.4/config/master/aws-k8s-cni.yaml" \
  -o "${MANIFESTS_DIR}/aws-vpc-cni.yaml"

echo "  Patching manifest for prefix delegation..."
python3 - "${MANIFESTS_DIR}/aws-vpc-cni.yaml" <<'PYEOF'
import sys, yaml

path = sys.argv[1]
with open(path) as f:
    docs = list(yaml.safe_load_all(f))

REMOVE_VARS = {"WARM_IP_TARGET", "MINIMUM_IP_TARGET"}
SET_VARS = {"ENABLE_PREFIX_DELEGATION": "true", "WARM_PREFIX_TARGET": "1", "WARM_ENI_TARGET": "0"}

for doc in docs:
    if not isinstance(doc, dict) or doc.get("kind") != "DaemonSet":
        continue
    for container in doc["spec"]["template"]["spec"].get("containers", []):
        env = [e for e in container.get("env", []) if e.get("name") not in REMOVE_VARS]
        seen = {e["name"] for e in env if e.get("name") in SET_VARS}
        for e in env:
            if e.get("name") in SET_VARS:
                e["value"] = SET_VARS[e["name"]]
        env += [{"name": k, "value": v} for k, v in SET_VARS.items() if k not in seen]
        container["env"] = env

with open(path, "w") as f:
    yaml.dump_all(docs, f, default_flow_style=False, allow_unicode=True)
PYEOF
sudo chown root:root "${MANIFESTS_DIR}/aws-vpc-cni.yaml"
echo "  ✓ Manifest patched (ENABLE_PREFIX_DELEGATION=true, WARM_PREFIX_TARGET=1, WARM_ENI_TARGET=0)"

# VPC CNI images live in a fixed account/region regardless of builder region.
# get-authorization-token --registry-ids is required to pull from 602401143452
# (cross-account ECR); get-login-password only works for the caller's own account.
VPC_CNI_ECR_REGION="us-west-2"
VPC_CNI_CTR_USER=$(aws ecr get-authorization-token \
  --registry-ids 602401143452 --region "${VPC_CNI_ECR_REGION}" \
  --query 'authorizationData[0].authorizationToken' --output text | base64 -d)

echo "  Pulling VPC CNI images (602401143452.dkr.ecr.us-west-2)..."
python3 "${EXTRACT_IMAGES_PY}" < "${MANIFESTS_DIR}/aws-vpc-cni.yaml" | sort -u | while read img; do
  sudo ctr -n k8s.io images pull --user "${VPC_CNI_CTR_USER}" "$img" || true
done

echo "  Pre-baking CNI binaries from init container..."
CNI_INIT_IMG=$(grep "image:" "${MANIFESTS_DIR}/aws-vpc-cni.yaml" | grep "cni-init" | head -1 | awk '{print $2}')
if [ -z "$CNI_INIT_IMG" ]; then
  echo "  ERROR: could not determine cni-init image from ${MANIFESTS_DIR}/aws-vpc-cni.yaml" >&2
  exit 1
fi

# The image must be fully present locally, otherwise we cannot extract from it.
# Fail the build here — do NOT fall through to a boot-time fallback, which only
# hides a broken bake and pushes the extraction cost onto every node's boot.
if ! sudo ctr -n k8s.io images check name=="$CNI_INIT_IMG" | grep -q "complete"; then
  echo "  ERROR: cni-init image ${CNI_INIT_IMG} not fully pulled; cannot pre-bake" >&2
  exit 1
fi

# Extract binaries via a read-only rootfs mount of the image (pure filesystem
# copy, exactly like 'docker cp'). This does NOT execute the container, so it
# works even though the minimal cni-init image has no usable shell/coreutils —
# the previous 'ctr run ... sh -c cp' approach silently copied 0 files because
# it depended on a shell inside the image.
sudo mkdir -p /opt/cni/bin
CNI_MNT="$(mktemp -d)"
sudo ctr -n k8s.io images mount "$CNI_INIT_IMG" "$CNI_MNT"
sudo cp -a "$CNI_MNT"/opt/cni/bin/. /opt/cni/bin/
sudo ctr -n k8s.io images unmount "$CNI_MNT"
rmdir "$CNI_MNT"

CNI_BIN_COUNT=$(ls /opt/cni/bin 2>/dev/null | wc -l)
if [ "$CNI_BIN_COUNT" -eq 0 ]; then
  echo "  ERROR: pre-bake copied 0 CNI binaries from ${CNI_INIT_IMG}" >&2
  exit 1
fi
echo "  ✓ CNI binaries baked to /opt/cni/bin (${CNI_BIN_COUNT} files)"

echo "✓ vpc-cni ready"
