#!/bin/bash
# install-cloud-provider.sh — Install AWS Cloud Controller Manager on k3s-Xpress.
# Called by setup-k3s-xpress.sh after k3s starts, before VPC CNI.
#
# The CCM is required for:
#   1. Setting node providerID to aws:///... (Karpenter needs this)
#   2. Removing node.cloudprovider.kubernetes.io/uninitialized taint
#   3. Node lifecycle management (instance metadata on node object)
#
# Same chart as EKS-D (09-install-cloud-provider.sh).
set -e

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

source /opt/k3s-xpress/cluster.env
source /opt/k3s-xpress/version.env

CHARTS_DIR="/opt/k3s-xpress/charts"

echo "  Installing AWS Cloud Controller Manager..."

CHART=$(ls "${CHARTS_DIR}"/aws-cloud-controller-manager-*.tgz 2>/dev/null | head -1)
if [ -z "$CHART" ]; then
  helm repo add aws-cloud-controller-manager https://kubernetes.github.io/cloud-provider-aws 2>/dev/null || true
  helm repo update aws-cloud-controller-manager
  CHART="aws-cloud-controller-manager/aws-cloud-controller-manager"
fi

helm upgrade --install aws-cloud-controller-manager "$CHART" \
  --namespace kube-system \
  --set nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
  --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
  --set tolerations[0].effect="NoSchedule" \
  --set tolerations[1].key="node.cloudprovider.kubernetes.io/uninitialized" \
  --set tolerations[1].effect="NoSchedule" \
  --set args[0]=--v=2 \
  --set args[1]=--cloud-provider=aws \
  --set args[2]=--configure-cloud-routes=false \
  --set args[3]=--cluster-name="${CLUSTER_NAME}" \
  --set hostNetworking=true \
  --wait --timeout=60s

# CCM may briefly deregister/re-register the node — retry until it appears
echo "  Waiting for CCM to initialize node..."
NODE_NAME=""
for i in $(seq 1 30); do
  NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [ -n "$NODE_NAME" ] && break
  sleep 2
done

if [ -z "$NODE_NAME" ]; then
  echo "  Warning: node not found after 60s — continuing without taint check"
elif kubectl get node "$NODE_NAME" -o jsonpath='{.spec.taints[*].key}' 2>/dev/null | grep -q "node.cloudprovider.kubernetes.io/uninitialized"; then
  echo "  Removing cloud provider uninitialized taint..."
  kubectl taint nodes "$NODE_NAME" node.cloudprovider.kubernetes.io/uninitialized- || true
  echo "  ✓ Cloud provider taint removed"
else
  echo "  ✓ Cloud provider taint not present or already removed"
fi

echo "  ✓ AWS Cloud Controller Manager installed"
