#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "==> Deploying EcpPackerIamGithubStack to ${CDK_DEFAULT_ACCOUNT}/${CDK_DEFAULT_REGION}..."

mvn -q compile

cdk deploy EcpPackerIamGithubStack \
  -c githubOrg=plasticity-of-cloud \
  -c githubRepo=express-compute \
  --require-approval never

echo "✓ Done"
