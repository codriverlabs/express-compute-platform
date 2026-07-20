#!/bin/bash
# 18-install-ecp-karpenter-support.sh
# Delegates to the canonical install script baked into the AMI at build time.
# Source: express-compute-control-plane release assets
#
# Prerequisites: cert-manager (11), Karpenter (15)
# Required env (via /opt/eks-d/cluster.env):
#   CLUSTER_NAME, TENANT_ID, AWS_REGION
set -eo pipefail

[ -f /opt/eks-d/cluster.env ] && source /opt/eks-d/cluster.env
[ -f /opt/eks-d/version.env ] && source /opt/eks-d/version.env

CANONICAL_SCRIPT="$(dirname "$0")/install-ecp-karpenter-support.sh"
if [ ! -f "$CANONICAL_SCRIPT" ]; then
  echo "Error: $CANONICAL_SCRIPT not found — was the AMI built correctly?"
  exit 1
fi

export CLUSTER_NAME TENANT_ID AWS_REGION ECP_CONTROL_PLANE_VERSION
export PUBLIC_SUBNET_ID PRIVATE_SUBNET_ID SECURITY_GROUP_ID
export CHART_DIR="/opt/cluster-setup/charts"

exec bash "$CANONICAL_SCRIPT"
