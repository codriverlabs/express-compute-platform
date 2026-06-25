#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-us-east-1}"
PROJECT_NAME="${2:-eks-dx-infra}"

echo "╔══════════════════════════════════════════════╗"
echo "║   EKS-DX Shared VPC — Deploy (CDK)           ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Region:  ${REGION}"
echo "  Project: ${PROJECT_NAME}"
echo ""

export CDK_DEFAULT_REGION="${REGION}"
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

CDK_DIR="$(dirname "$0")/infra"

echo "==> Bootstrapping CDK environment (idempotent)..."
cdk bootstrap "aws://${CDK_DEFAULT_ACCOUNT}/${REGION}" --quiet
echo "    ✓ CDK bootstrap complete"

echo ""
echo "==> Building CDK bundle (mvn compile)..."
mvn -e -q clean compile -f "${CDK_DIR}/pom.xml"
echo "    ✓ CDK bundle built"

echo ""
echo "==> Synthesizing CloudFormation template..."
cd "${CDK_DIR}"
cdk synth EksDxSharedInfraStack \
  --context projectName="${PROJECT_NAME}" \
  --quiet
echo "    ✓ Template: cdk/cdk.out/EksDxSharedInfraStack.template.json"

echo ""
echo "==> Deploying shared infrastructure..."
cdk deploy EksDxSharedInfraStack \
  --context projectName="${PROJECT_NAME}" \
  --require-approval never

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   Shared infrastructure deployed             ║"
echo "╚══════════════════════════════════════════════╝"
