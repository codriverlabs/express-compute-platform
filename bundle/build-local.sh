#!/usr/bin/env bash
# Build the Express Compute bundle image locally.
# Downloads release artifacts from GitHub using versions in bundle-versions.env.
#
# Usage:
#   ./bundle/build-local.sh [IMAGE_TAG]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build"
IMAGE_TAG="${1:-express-compute-bundle:local}"

source "${SCRIPT_DIR}/bundle-versions.env"

CP_VER="${CONTROL_PLANE_VERSION}"
INFRA_VER="${INFRA_VERSION}"
ARCH=$(uname -m); [ "${ARCH}" = "aarch64" ] && ARCH="arm64" || ARCH="amd64"

CP_BASE="https://github.com/codriverlabs/express-compute-control-plane/releases/download/v${CP_VER}"
INFRA_BASE="https://github.com/codriverlabs/express-compute-managed-k8s-infra/releases/download/v${INFRA_VER}"

# ── Authenticate to ECR public gallery (required to pull base image) ─────────
echo "==> Authenticating to ECR public gallery..."
aws ecr-public get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin public.ecr.aws

# ── Download artifacts ───────────────────────────────────────────────────────
echo "==> Downloading control-plane v${CP_VER}..."
rm -rf "${BUILD_DIR}" && mkdir -p "${BUILD_DIR}/helm"

# control-plane tarball has a versioned top-level dir — strip it
curl -fsSL "${CP_BASE}/express-compute-control-plane-${CP_VER}.tar.gz" \
  | tar xz -C "${BUILD_DIR}" --strip-components=1 --one-top-level=control-plane-cdk

echo "==> Downloading infra v${INFRA_VER}..."
# infra tarball has no top-level dir — extract directly
mkdir -p "${BUILD_DIR}/infra-cdk"
curl -fsSL "${INFRA_BASE}/express-compute-managed-k8s-infra-${INFRA_VER}.tar.gz" \
  | tar xz -C "${BUILD_DIR}/infra-cdk"

echo "==> Downloading ecp CLI (${ARCH})..."
curl -fsSL "${CP_BASE}/ecp-cli-${CP_VER}-linux-${ARCH}" \
  -o "${BUILD_DIR}/ecp-cli"
chmod +x "${BUILD_DIR}/ecp-cli"

echo "==> Downloading Helm charts..."
for chart in express-compute-auth-proxy express-compute-workload-identity-webhook express-compute-karpenter-support; do
  curl -fsSL "${CP_BASE}/${chart}-${CP_VER}.tar.gz" \
    -o "${BUILD_DIR}/helm/${chart}-${CP_VER}.tar.gz"
done

# AMI manifest from this repo's latest release (or empty stub for local dev)
if [ -f "${ROOT}/ami-manifest.json" ]; then
  cp "${ROOT}/ami-manifest.json" "${BUILD_DIR}/ami-manifest.json"
else
  echo '{}' > "${BUILD_DIR}/ami-manifest.json"
  echo "  Warning: no ami-manifest.json — using empty stub"
fi

# AMI signatures + public key (for verify-ami / import-ami)
[ -f "${ROOT}/ami-signatures.json" ] \
  && cp "${ROOT}/ami-signatures.json" "${BUILD_DIR}/ami-signatures.json" \
  || echo '{}' > "${BUILD_DIR}/ami-signatures.json"
cp "${ROOT}/ami-builder/express-compute-ami-signing.pub.pem" "${BUILD_DIR}/express-compute-ami-signing.pub.pem"

# AMI utility scripts
cp "${ROOT}/ami-builder/scripts/verify-ami.sh" "${BUILD_DIR}/verify-ami.sh"
cp "${ROOT}/ami-builder/scripts/import-ami.sh" "${BUILD_DIR}/import-ami.sh"

cp "${SCRIPT_DIR}/Dockerfile" "${BUILD_DIR}/Dockerfile"
cp "${SCRIPT_DIR}/deploy.sh"  "${BUILD_DIR}/deploy.sh"

# ── Build ────────────────────────────────────────────────────────────────────
echo "==> Building ${IMAGE_TAG}..."
docker build -t "${IMAGE_TAG}" "${BUILD_DIR}"

echo ""
echo "✓ Built ${IMAGE_TAG}"
echo ""
echo "Run interactively (credentials file):"
echo "  docker run --rm -it -v ~/.aws:/root/.aws:ro --entrypoint bash -e AWS_REGION=us-east-1 ${IMAGE_TAG}"
echo ""
echo "Run interactively (env vars / EC2 / CloudShell):"
echo "  docker run --rm -it -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION=us-east-1 --entrypoint bash ${IMAGE_TAG}"
