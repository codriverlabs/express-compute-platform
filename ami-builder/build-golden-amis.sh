#!/usr/bin/env bash
# Interactive wrapper for local AMI builds — delegates to ami-builder/Makefile.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

prompt() {
  local var="$1" msg="$2" default="$3"
  [ -n "${!var:-}" ] && { echo "    ${msg}: ${!var} (from env)"; return; }
  read -rp "  ${msg} [${default}]: " input
  printf -v "$var" '%s' "${input:-$default}"
}

AWS_REGION="${AWS_REGION:-}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-}"
ARCH="${ARCH:-arm64}"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   EKS-DX Distribution — Build AMI           ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
prompt AWS_REGION         "AWS region"         "us-east-1"
prompt KUBERNETES_VERSION "Kubernetes version" "1.35"
prompt ARCH               "Architecture"       "arm64"

make -C "${SCRIPT_DIR}" ami \
  AWS_REGION="${AWS_REGION}" \
  KUBERNETES_VERSION="${KUBERNETES_VERSION}" \
  ARCH="${ARCH}"
