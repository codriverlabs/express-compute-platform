#!/usr/bin/env bash
# Build the EKS-D-Xpress bundle image locally.
#
# Expects the following repos to be checked out as siblings of this repo:
#   ../eks-d-xpress-control-plane
#   ../eks-d-xpress-infra
#
# Usage:
#   ./bundle/build-local.sh [IMAGE_TAG]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build"
IMAGE_TAG="${1:-eks-d-xpress-bundle:local}"

CONTROL_PLANE_DIR="${ROOT}/../eks-d-xpress-control-plane"
INFRA_DIR="${ROOT}/../eks-d-xpress-infra"

# ── Validate sibling repos ───────────────────────────────────────────────────
[ -d "${CONTROL_PLANE_DIR}" ] || { echo "ERROR: ${CONTROL_PLANE_DIR} not found"; exit 1; }
[ -d "${INFRA_DIR}" ]         || { echo "ERROR: ${INFRA_DIR} not found"; exit 1; }

# ── Authenticate to ECR public gallery (required to pull base image) ─────────
echo "==> Authenticating to ECR public gallery..."
aws ecr-public get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin public.ecr.aws

# ── Stage build context ──────────────────────────────────────────────────────
echo "==> Staging build context in ${BUILD_DIR}..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/helm"

# Control-plane CDK source
cp -r "${CONTROL_PLANE_DIR}" "${BUILD_DIR}/control-plane-cdk"

# Infra CDK (pre-synthesized cdk.out expected in the infra repo)
cp -r "${INFRA_DIR}" "${BUILD_DIR}/infra-cdk"

# CLI binary (use native arch)
ARCH=$(uname -m)
[ "${ARCH}" = "aarch64" ] && ARCH="arm64" || ARCH="amd64"
CLI_BIN=$(find "${CONTROL_PLANE_DIR}" -name "eks-dx-cli*-linux-${ARCH}" 2>/dev/null | head -1)
if [ -z "${CLI_BIN}" ]; then
  echo "ERROR: eks-dx-cli binary not found in ${CONTROL_PLANE_DIR}"
  echo "       Build the control-plane project first or download the release binary."
  exit 1
fi
cp "${CLI_BIN}" "${BUILD_DIR}/eks-dx-cli"

# Helm charts
find "${CONTROL_PLANE_DIR}" -name "eks-d-xpress-*.tar.gz" -exec cp {} "${BUILD_DIR}/helm/" \; 2>/dev/null || true

# AMI manifest (use latest from this repo, or a stub if not present)
if [ -f "${ROOT}/ami-manifest.json" ]; then
  cp "${ROOT}/ami-manifest.json" "${BUILD_DIR}/ami-manifest.json"
else
  echo '{}' > "${BUILD_DIR}/ami-manifest.json"
  echo "  Warning: no ami-manifest.json found — using empty stub"
fi

# Dockerfile + orchestrator
cp "${SCRIPT_DIR}/Dockerfile" "${BUILD_DIR}/Dockerfile"
cp "${SCRIPT_DIR}/deploy.sh"   "${BUILD_DIR}/deploy.sh"

# ── Build ────────────────────────────────────────────────────────────────────
echo "==> Building ${IMAGE_TAG}..."
docker build -t "${IMAGE_TAG}" "${BUILD_DIR}"

echo ""
echo "✓ Built ${IMAGE_TAG}"
echo ""
echo "Run interactively (credentials file):"
echo "  docker run --rm -it -v ~/.aws:/root/.aws:ro -e AWS_REGION=us-east-1 ${IMAGE_TAG} bash"
echo ""
echo "Run interactively (env vars / EC2 / CloudShell):"
echo "  docker run --rm -it -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION=us-east-1 ${IMAGE_TAG} bash"
