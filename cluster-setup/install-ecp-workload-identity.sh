#!/usr/bin/env bash
# install-ecp-workload-identity.sh
#
# Installs EKS Workload Identity on any Kubernetes distribution (k3s, EKS-D, microk8s, etc.)
# by registering the cluster with the ecp control plane and deploying three components:
#   1. ecp-auth-proxy      — in-cluster TokenReview + credential forwarding
#   2. ecp-workload-identity-webhook — mutating webhook (env + projected token injection)
#   3. eks-workload-identity-agent — AWS DaemonSet (intercepts 169.254.170.23)
#
# Required environment variables:
#   CLUSTER_NAME                 — unique cluster identifier
#   AWS_REGION                   — AWS region
#   ECP_CONTROL_PLANE_VERSION — ecp-control-plane release version (sourced from /opt/eks-d/version.env)
#
# Optional environment variables:
#   ECP_ENDPOINT              — API Gateway URL override (default: resolved from SSM /express-compute/control-plane/api/endpoint)
#   KUBECONFIG                   — path to kubeconfig (default: standard lookup)
#   CHART_DIR                    — directory containing pre-downloaded chart tarballs (AMI bake path)
#                                  falls back to GHCR OCI pull if not set or charts not found
#
# Usage:
#   curl -sL https://github.com/plasticity-of-cloud/express-compute-control-plane/releases/download/vVERSION/install-ecp-workload-identity.sh \
#     | CLUSTER_NAME=my-cluster AWS_REGION=us-east-1 bash
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

# ── Parse --oidc-mode flag ─────────────────────────────────────────────────────
OIDC_MODE="self-managed"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --oidc-mode) OIDC_MODE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# ── Validate required inputs ───────────────────────────────────────────────────
[[ -z "${CLUSTER_NAME:-}"    ]] && err "CLUSTER_NAME is required"
[[ -z "${AWS_REGION:-}"      ]] && err "AWS_REGION is required"

# ── Resolve ECP_ENDPOINT (env → SSM → error) ───────────────────────────────
if [[ -z "${ECP_ENDPOINT:-}" ]]; then
  ECP_ENDPOINT=$(aws ssm get-parameter \
    --name /express-compute/control-plane/api/endpoint \
    --region "${AWS_REGION}" \
    --query Parameter.Value --output text 2>/dev/null || true)
fi
[[ -z "${ECP_ENDPOINT:-}" ]] && err "ECP_ENDPOINT could not be resolved — set env var or ensure SSM param /express-compute/control-plane/api/endpoint exists"

[[ -z "${ECP_CONTROL_PLANE_VERSION:-}" ]] && err "ECP_CONTROL_PLANE_VERSION is required — set it explicitly or ensure /opt/eks-d/version.env is present"

CHART_DIR="${CHART_DIR:-/opt/cluster-setup/charts}"

ECP_GHCR_REGISTRY="${ECP_GHCR_REGISTRY:-ghcr.io/plasticity-of-cloud}"

log "Express Compute Workload Identity installation"
log "  Cluster:  ${CLUSTER_NAME}"
log "  Region:   ${AWS_REGION}"
log "  Endpoint: ${ECP_ENDPOINT}"
log "  Version:  ${ECP_CONTROL_PLANE_VERSION}"

# ── Helper: resolve chart (local cache first, GHCR OCI fallback) ──────────────
chart_ref() {
  local name="$1"
  local tgz
  #tgz=$(ls "${CHART_DIR}/${name}"-*.tgz 2>/dev/null | head -1 || true)
  tgz=$(ls "${CHART_DIR}/${name}"-*.tgz "${CHART_DIR}/${name}"-*.tar.gz 2>/dev/null | head -1 || true)
  if [[ -n "$tgz" ]]; then
    echo "$tgz"
  else
    echo "oci://${ECP_GHCR_REGISTRY}/helm/${name} --version ${ECP_CONTROL_PLANE_VERSION}"
  fi
}

# ── 0. cert-manager (required for webhook TLS) ────────────────────────────────
if ! kubectl get crd certificates.cert-manager.io &>/dev/null; then
  log "Installing cert-manager..."
  helm repo add jetstack https://charts.jetstack.io --force-update 2>/dev/null
  helm repo update jetstack 2>/dev/null
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --set crds.enabled=true \
    --wait --timeout=120s
  log "✓ cert-manager installed"
else
  log "✓ cert-manager already present"
fi

# ── 1. Register cluster (self-managed only — managed clusters are pre-registered) ──
if [[ "$OIDC_MODE" == "self-managed" ]]; then
  log "Registering cluster with ecp control plane..."

  ISSUER=$(kubectl get --raw /.well-known/openid-configuration 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['issuer'])" 2>/dev/null || true)
  [[ -z "$ISSUER" ]] && ISSUER="${ECP_ENDPOINT}/clusters/${CLUSTER_NAME}"

  kubectl get --raw /openid/v1/jwks > /tmp/ecp-jwks.json

  ecp create-cluster --name "${CLUSTER_NAME}" --oidc-mode self-managed \
    --region "${AWS_REGION}" \
    --issuer "${ISSUER}" \
    --jwks-file /tmp/ecp-jwks.json || warn "Cluster registration returned non-zero (may already be registered)"

  rm -f /tmp/ecp-jwks.json
  log "✓ Cluster registered"
else
  log "Skipping cluster registration (managed mode — pre-registered by control plane)"
fi

# ── 2. ecp-auth-proxy ──────────────────────────────────────────────────────
log "Installing ecp-auth-proxy..."
# shellcheck disable=SC2046
helm upgrade --install express-compute-auth-proxy $(chart_ref express-compute-auth-proxy) \
  --namespace kube-system \
  --set app.envs.ECP_ENDPOINT="${ECP_ENDPOINT}" \
  --set app.envs.AWS_REGION="${AWS_REGION}" \
  --wait --timeout=120s
log "✓ ecp-auth-proxy installed"

# ── 3. ecp-workload-identity-webhook ───────────────────────────────────────────
log "Installing ecp-workload-identity-webhook..."
# shellcheck disable=SC2046
helm upgrade --install express-compute-workload-identity-webhook $(chart_ref express-compute-workload-identity-webhook) \
  --namespace kube-system \
  --set app.envs.ECP_ENDPOINT="${ECP_ENDPOINT}" \
  --set app.envs.EKS_CLUSTER_NAME="${CLUSTER_NAME}" \
  --set app.envs.AWS_REGION="${AWS_REGION}" \
  --wait --timeout=120s
log "✓ ecp-workload-identity-webhook installed"

# ── 4. eks-workload-identity-agent ─────────────────────────────────────────────────
# The agent image is in AWS ECR us-west-2 — create a pull secret.
log "Creating ECR pull secret for eks-workload-identity-agent..."
kubectl create secret docker-registry ecr-workload-identity-agent \
  --namespace kube-system \
  --docker-server=602401143452.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region us-west-2)" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Installing eks-workload-identity-agent..."
AGENT_CHART=$(ls "${CHART_DIR}/eks-workload-identity-agent"-*.tgz 2>/dev/null | head -1 || true)
if [[ -z "$AGENT_CHART" ]]; then
  warn "eks-workload-identity-agent chart not in CHART_DIR — downloading from GitHub..."
  mkdir -p /tmp/eks-workload-identity-agent
  curl -sL https://github.com/aws/eks-workload-identity-agent/archive/refs/heads/main.tar.gz | \
    tar xz --strip-components=3 -C /tmp/eks-workload-identity-agent eks-workload-identity-agent-main/charts/eks-workload-identity-agent
  AGENT_CHART="/tmp/eks-workload-identity-agent"
fi

helm upgrade --install eks-workload-identity-agent "$AGENT_CHART" \
  --namespace kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set env.AWS_REGION="${AWS_REGION}" \
  --set "agent.additionalArgs.--endpoint=http://ecp-auth-proxy.kube-system.svc.cluster.local:8080" \
  --set "affinity=" \
  --set "imagePullSecrets[0].name=ecr-workload-identity-agent" \
  --wait --timeout=120s
log "✓ eks-workload-identity-agent installed"

log "Express Compute Workload Identity installation complete"
log "  Test: kubectl run aws-test --image=amazon/aws-cli:latest --rm -it \\"
log "    --overrides='{\"spec\":{\"serviceAccountName\":\"<your-sa\"}}' -- sts get-caller-identity"
