#!/bin/bash
set -e

# Install cert-manager for TLS certificate lifecycle management.
# Required by: CloudWatch Observability webhooks, custom admission webhooks,
# and future EKS Pod Identity Agent integration.

# Source component versions (single source of truth for all component versions)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_ENV="${SCRIPT_DIR}/../ami-builder/scripts/component-versions.env"
[ -f "$VERSIONS_ENV" ] && source "$VERSIONS_ENV"
: "${CERT_MANAGER_VERSION:?CERT_MANAGER_VERSION not set — component-versions.env missing or incomplete}"

echo "Installing cert-manager ${CERT_MANAGER_VERSION}..."

# Use pre-cached chart if available
CHART=$(ls /opt/eks-d-setup/charts/cert-manager-*.tgz 2>/dev/null | head -1)
if [ -z "$CHART" ]; then
  CHART="jetstack/cert-manager"
  helm repo add jetstack https://charts.jetstack.io --force-update
  helm repo update jetstack
fi

helm upgrade --install cert-manager "$CHART" \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --timeout=60s

# Only wait for the webhook — it's the slowest component (TLS cert generation).
kubectl wait --for=condition=available deployment/cert-manager-webhook -n cert-manager --timeout=40s || {
  echo "Warning: cert-manager-webhook not ready within timeout"
}

echo "✓ cert-manager installed"
kubectl get pods -n cert-manager

# Approve pending kubelet serving CSRs — cert-manager webhook registration
# causes the kubelet to generate a new serving CSR; must be approved for
# webhook TLS to work. Retry loop handles the timing gap.
echo "Approving pending kubelet serving CSRs..."
for i in $(seq 1 10); do
  PENDING=$(kubectl get csr --no-headers 2>/dev/null | awk '/Pending/{print $1}')
  if [ -n "$PENDING" ]; then
    echo "$PENDING" | xargs kubectl certificate approve
    echo "✓ CSRs approved"
    break
  fi
  [ "$i" -eq 10 ] && echo "Warning: no pending CSRs found after 30s" || sleep 3
done
