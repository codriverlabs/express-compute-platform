#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "==> Deploying ExpressComputePackerIamGithubStack to ${CDK_DEFAULT_ACCOUNT}/${CDK_DEFAULT_REGION}..."

mvn -q compile

cdk deploy ExpressComputePackerIamGithubStack \
  -c githubOrg=codriverlabs \
  -c githubOrgId=236268168 \
  -c githubRepo=express-compute-platform \
  -c githubRepoId=1250509430 \
  --require-approval never

echo "✓ Done"
