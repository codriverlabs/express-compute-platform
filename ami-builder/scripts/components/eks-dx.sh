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
  helm pull "oci://${GHCR_EKS_D_XPRESS_REGISTRY}/helm/${chart}" \
    --version "${ECP_CONTROL_PLANE_VERSION}" --destination /tmp || true
done
sudo mv /tmp/express-compute-*.tgz "${CHARTS_DIR}/" 2>/dev/null || true

echo "  Pulling Express Compute container images..."
sudo ctr -n k8s.io images pull \
  "${GHCR_EKS_D_XPRESS_REGISTRY}/express-compute-auth-proxy:${ECP_CONTROL_PLANE_VERSION}" || true
sudo ctr -n k8s.io images pull \
  "${GHCR_EKS_D_XPRESS_REGISTRY}/express-compute-workload-identity-webhook:${ECP_CONTROL_PLANE_VERSION}" || true

echo "  Pulling eks-workload-identity-agent chart..."
mkdir -p /tmp/eks-workload-identity-agent
curl -sL https://github.com/aws/eks-workload-identity-agent/archive/refs/heads/main.tar.gz | \
  tar xz --strip-components=3 -C /tmp/eks-workload-identity-agent \
    eks-workload-identity-agent-main/charts/eks-workload-identity-agent || true
if [ -f /tmp/eks-workload-identity-agent/Chart.yaml ]; then
  helm package /tmp/eks-workload-identity-agent --destination /tmp || true
  sudo mv /tmp/eks-workload-identity-agent-*.tgz "${CHARTS_DIR}/" 2>/dev/null || true
fi
rm -rf /tmp/eks-workload-identity-agent

echo "  Pulling eks-workload-identity-agent image..."
EKS_POD_ID_CTR_USER=$(aws ecr get-authorization-token \
  --registry-ids 602401143452 --region us-west-2 \
  --query 'authorizationData[0].authorizationToken' --output text | base64 -d)
sudo ctr -n k8s.io images pull \
  --user "${EKS_POD_ID_CTR_USER}" \
  "602401143452.dkr.ecr.us-west-2.amazonaws.com/eks/eks-workload-identity-agent:v1.3.10-eksbuild.3" || true

echo "✓ ecp ready"
