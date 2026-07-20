#!/bin/bash
# 12-install-ecp-workload-identity.sh
# Delegates to the canonical install script baked into the AMI at build time.
# Source: express-compute-control-plane release assets
#
# Prerequisites: cert-manager (11-install-cert-manager.sh)
# Required env (via /opt/eks-d/cluster.env):
#   ECP_ENDPOINT, CLUSTER_NAME, AWS_REGION
set -eo pipefail

[ -f /opt/eks-d/cluster.env ]  && source /opt/eks-d/cluster.env
[ -f /opt/eks-d/version.env ]  && source /opt/eks-d/version.env

if [[ "${INSTALL_ECP:-false}" != "true" ]]; then
  echo "Skipping Express Compute Workload Identity (INSTALL_ECP != true)"
  exit 0
fi

if [ -z "${ECP_ENDPOINT:-}" ]; then
  echo "Skipping Express Compute Workload Identity (ECP_ENDPOINT not set)"
  exit 0
fi

CANONICAL_SCRIPT="$(dirname "$0")/install-ecp-workload-identity.sh"
if [ ! -f "$CANONICAL_SCRIPT" ]; then
  echo "Error: $CANONICAL_SCRIPT not found — was the AMI built correctly?"
  exit 1
fi

export ECP_ENDPOINT CLUSTER_NAME AWS_REGION ECP_CONTROL_PLANE_VERSION
export CHART_DIR="/opt/cluster-setup/charts"

exec bash "$CANONICAL_SCRIPT" --oidc-mode managed
