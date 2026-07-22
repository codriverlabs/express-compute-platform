#!/bin/bash
set -e
source /tmp/ami-build.env
CHARTS_DIR="/opt/cluster-setup/charts"

if [[ "${INSTALL_ECP:-false}" != "true" ]]; then
  echo "  Skipping Express Compute components (INSTALL_ECP=false)"
  echo "✓ ecp skipped"
  exit 0
fi

echo "  Pulling Express Compute Helm charts (v${ECP_CONTROL_PLANE_VERSION})..."
for chart in express-compute-workload-identity-webhook express-compute-auth-proxy express-compute-karpenter-support; do
  helm pull "oci://${ECP_GHCR_REGISTRY}/helm/${chart}" \
    --version "${ECP_CONTROL_PLANE_VERSION}" --destination /tmp || true
done
sudo mv /tmp/express-compute-*.tgz "${CHARTS_DIR}/" 2>/dev/null || true

echo "  Pulling Express Compute container images..."
sudo ctr -n k8s.io images pull \
  "${ECP_GHCR_REGISTRY}/express-compute-auth-proxy:${ECP_CONTROL_PLANE_VERSION}" || true
sudo ctr -n k8s.io images pull \
  "${ECP_GHCR_REGISTRY}/express-compute-workload-identity-webhook:${ECP_CONTROL_PLANE_VERSION}" || true

echo "  Pulling eks-pod-identity-agent chart..."
mkdir -p /tmp/eks-pod-identity-agent
curl -sL https://github.com/aws/eks-pod-identity-agent/archive/refs/heads/main.tar.gz | \
  tar xz --strip-components=3 -C /tmp/eks-pod-identity-agent \
    eks-pod-identity-agent-main/charts/eks-pod-identity-agent || true
if [ -f /tmp/eks-pod-identity-agent/Chart.yaml ]; then
  helm package /tmp/eks-pod-identity-agent --destination /tmp || true
  sudo mv /tmp/eks-pod-identity-agent-*.tgz "${CHARTS_DIR}/" 2>/dev/null || true
fi
rm -rf /tmp/eks-pod-identity-agent

echo "  Pulling eks-pod-identity-agent images (auto-discovered from chart)..."
AGENT_CHART=$(ls "${CHARTS_DIR}"/eks-pod-identity-agent-*.tgz 2>/dev/null | head -1 || true)
if [[ -n "$AGENT_CHART" ]]; then
  EKS_POD_ID_CTR_USER=$(aws ecr get-authorization-token \
    --registry-ids 602401143452 --region us-west-2 \
    --query 'authorizationData[0].authorizationToken' --output text | base64 -d)
  helm template eks-pod-identity-agent "$AGENT_CHART" 2>/dev/null | \
    python3 "${EXTRACT_IMAGES_PY}" | sort -u | while read img; do
      sudo ctr -n k8s.io images pull --user "${EKS_POD_ID_CTR_USER}" "$img" || true
    done
fi

echo "✓ ecp ready"
