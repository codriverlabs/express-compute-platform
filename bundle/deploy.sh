#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="express-compute-managed-k8s-infra"
DEPLOYMENT_MODE="hybrid"
INSTANCE_TYPE_ARM64="c6g.xlarge"
INSTANCE_TYPE_X86="m7i.large"
DISK_SIZE_GB="20"
ENABLE_NAT_GATEWAY="false"
K8S_VERSION="1.35"
ARCH="arm64"

usage() {
  cat <<EOF
Express Compute Deployment Bundle

Usage:
  deploy.sh deploy [--stack <name>] [--region <region>] [--project-name <n>]
                   [--deployment-mode <mode>]
                   [--instance-type-arm64 <type>] [--instance-type-x86 <type>]
                   [--disk-size-gb <n>] [--enable-nat-gateway]
                   [--domain-name <fqdn>] [--certificate-arn <arn>]
                   [--k8s-version <ver>] [--arch <arch>]
  deploy.sh destroy [--stack <name>] [--region <region>]
  deploy.sh register-amis [--region <region>] [--k8s-version <ver>] [--arch <arch>]
  deploy.sh install-charts [--kubeconfig <path>]
  deploy.sh verify-ami --ami-id <id> [--sig-file <path>]
  deploy.sh import-ami --ami-id <id> --src-region <r> --regions <r1,r2>
  deploy.sh --help

  Cluster management: use 'ecp' directly (on PATH). Run 'ecp --help' for commands.

Deployment Modes:
  self-managed    Control plane only (Workload Identity for existing clusters)
  managed         Full deployment including managed k8s infrastructure
  hybrid          Both flows enabled (default)

Stacks:
  infra           Shared VPC infrastructure (skipped in self-managed mode)
  control-plane   Serverless control plane (Lambdas, API GW, DynamoDB)
  all             Deploy all applicable stacks in order (default)

AMI Filtering (defaults: --arch=arm64, --k8s-version=1.35):
  --k8s-version   Import only AMIs for this Kubernetes version (e.g. "1.35")
  --arch          Import only AMIs for this architecture ("arm64" or "x86_64")

Examples:
  deploy.sh deploy --region eu-west-1
  deploy.sh deploy --region eu-west-1 --k8s-version 1.35 --arch arm64
  deploy.sh deploy --deployment-mode self-managed
  deploy.sh deploy --stack infra
  deploy.sh destroy --stack control-plane
  deploy.sh register-amis --region us-east-1 --arch arm64
  deploy.sh verify-ami --ami-id ami-0abc1234def56789
  deploy.sh import-ami --ami-id ami-0abc1234def56789 --src-region us-east-1 --regions us-east-1,eu-west-1
  ecp list-clusters    # use ecp directly (on PATH)
EOF
  exit 0
}

cdk_bootstrap() {
  local account
  account=$(aws sts get-caller-identity --query Account --output text)
  echo "==> CDK Bootstrap (aws://${account}/${REGION})"
  cdk bootstrap "aws://${account}/${REGION}" --quiet 2>/dev/null || true
}

deploy_infra() {
  echo "==> Deploying ExpressComputeManagedK8sInfraStack"
  cd "${SCRIPT_DIR}/infra"
  cdk deploy --app cdk.out --all --require-approval never \
    --region "${REGION}" \
    --parameters "ExpressComputeManagedK8sInfraStack:Region=${REGION}" \
    --parameters "ExpressComputeManagedK8sInfraStack:ProjectName=${PROJECT_NAME}" \
    --parameters "ExpressComputeManagedK8sInfraStack:InstanceTypeArm64=${INSTANCE_TYPE_ARM64}" \
    --parameters "ExpressComputeManagedK8sInfraStack:InstanceTypeX86=${INSTANCE_TYPE_X86}" \
    --parameters "ExpressComputeManagedK8sInfraStack:DiskSizeGb=${DISK_SIZE_GB}" \
    --parameters "ExpressComputeManagedK8sInfraStack:EnableNatGateway=${ENABLE_NAT_GATEWAY}"
}

deploy_control_plane() {
  echo "==> Deploying ExpressComputeControlPlaneStack (mode: ${DEPLOYMENT_MODE})"
  cd "${SCRIPT_DIR}/control-plane"
  local params=()
  [[ -n "${DOMAIN_NAME:-}" ]]      && params+=(--parameters "ExpressComputeControlPlaneStack:DomainName=${DOMAIN_NAME}")
  [[ -n "${CERTIFICATE_ARN:-}" ]]  && params+=(--parameters "ExpressComputeControlPlaneStack:CertificateArn=${CERTIFICATE_ARN}")
  cdk deploy --app cdk.out --all --require-approval never \
    --region "${REGION}" \
    --context "deploymentMode=${DEPLOYMENT_MODE}" \
    "${params[@]}"
}

register_amis() {
  echo "==> Registering golden AMI IDs to SSM"
  local manifest="${SCRIPT_DIR}/ami-manifest.json"
  [[ -f "$manifest" ]] || { echo "ERROR: ami-manifest.json not found"; exit 1; }

  local filter_k8s_version="${K8S_VERSION:-}"
  local filter_arch="${ARCH:-}"
  [[ -n "$filter_k8s_version" ]] && echo "    Filtering: k8s-version=${filter_k8s_version}"
  [[ -n "$filter_arch" ]]        && echo "    Filtering: arch=${filter_arch}"

  python3 -c "
import json, subprocess, os, sys

region = os.environ.get('AWS_REGION', 'us-east-1')
filter_k8s_version = '${filter_k8s_version}'
filter_arch = '${filter_arch}'
manifest = json.load(open('${manifest}'))

for k8s_ver, arches in manifest.items():
    if filter_k8s_version and k8s_ver != filter_k8s_version:
        continue
    for arch, regions_map in arches.items():
        if filter_arch and arch != filter_arch:
            continue
        # Find the AMI — check if one exists for the target region directly
        ami_id = regions_map.get(region)
        src_region = region

        if not ami_id:
            # AMI not built for this region — find it in another region and copy
            src_region, ami_id = next(iter(regions_map.items()), (None, None))
            if not ami_id:
                print(f'  SKIP: No AMI for {arch}/{k8s_ver} in any region')
                continue

            print(f'  Importing {ami_id} ({arch}/{k8s_ver}) from {src_region} to {region}...')

            # Verify signature before importing
            subprocess.run([
                '${SCRIPT_DIR}/bin/verify-ami.sh',
                '--ami-id', ami_id,
                '--sig-file', '${SCRIPT_DIR}/ami-signatures.json',
                '--pubkey', '${SCRIPT_DIR}/express-compute-ami-signing.pub.pem'
            ], check=True)

            # Check if already imported by looking for tag with source AMI ID
            check = subprocess.run([
                'aws', 'ec2', 'describe-images',
                '--region', region,
                '--owners', 'self',
                '--filters',
                f'Name=tag:SourceAmiId,Values={ami_id}',
                'Name=state,Values=available',
                '--query', 'Images[0].ImageId',
                '--output', 'text'
            ], capture_output=True, text=True)
            existing = check.stdout.strip()
            if existing and existing != 'None':
                print(f'  ✓ Already imported: {existing} (source: {ami_id})')
                ami_id = existing
            else:
                # Copy from source region (works because AMI is public)
                result = subprocess.run([
                    'aws', 'ec2', 'copy-image',
                    '--source-image-id', ami_id,
                    '--source-region', src_region,
                    '--region', region,
                    '--name', f'express-compute-{arch}-imported-{k8s_ver}',
                    '--description', f'Express Compute k8s-{k8s_ver} {arch} imported from {src_region}',
                    '--query', 'ImageId', '--output', 'text'
                ], capture_output=True, text=True, check=True)
                new_ami_id = result.stdout.strip()
                print(f'  ✓ Copy started: {new_ami_id} (async — will wait)')

                # Wait for the copy to complete
                print(f'    Waiting for {new_ami_id} to become available...')
                subprocess.run([
                    'aws', 'ec2', 'wait', 'image-available',
                    '--region', region,
                    '--image-ids', new_ami_id
                ], check=True)
                print(f'    ✓ {new_ami_id} available')

                # Tag with source provenance for idempotent re-runs
                subprocess.run([
                    'aws', 'ec2', 'create-tags',
                    '--region', region,
                    '--resources', new_ami_id,
                    '--tags',
                    f'Key=SourceAmiId,Value={ami_id}',
                    f'Key=SourceRegion,Value={src_region}',
                    f'Key=KubernetesVersion,Value={k8s_ver}',
                    f'Key=Architecture,Value={arch}',
                    'Key=ManagedBy,Value=express-compute',
                ], check=True)
                ami_id = new_ami_id

        # Register in SSM (only if value changed)
        param = f'/express-compute/infra/ami/{arch}/{k8s_ver}'
        current = subprocess.run([
            'aws', 'ssm', 'get-parameter',
            '--name', param,
            '--region', region,
            '--query', 'Parameter.Value',
            '--output', 'text'
        ], capture_output=True, text=True)
        if current.returncode == 0 and current.stdout.strip() == ami_id:
            print(f'  ✓ {param} = {ami_id} (unchanged)')
        else:
            subprocess.run([
                'aws', 'ssm', 'put-parameter',
                '--name', param,
                '--value', ami_id,
                '--type', 'String',
                '--overwrite',
                '--region', region
            ], check=True)
            print(f'  ✓ {param} = {ami_id}')
"
}

install_charts() {
  echo "==> Installing Helm charts"
  local kubeconfig="${KUBECONFIG:-/root/.kube/config}"
  for chart in "${SCRIPT_DIR}"/helm/*.tar.gz; do
    [[ -f "$chart" ]] || continue
    echo "  Installing $(basename "$chart")"
    helm upgrade --install "$(basename "$chart" .tar.gz)" "$chart" \
      --kubeconfig "$kubeconfig" \
      --create-namespace
  done
}

# ─── Main ───────────────────────────────────────────────────────────
COMMAND="${1:-}"
[[ -z "$COMMAND" || "$COMMAND" == "--help" || "$COMMAND" == "-h" ]] && usage
shift

STACK="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)               STACK="$2";                  shift 2 ;;
    --region)              REGION="$2"; export AWS_REGION="$2"; shift 2 ;;
    --deployment-mode)     DEPLOYMENT_MODE="$2";        shift 2 ;;
    --project-name)        PROJECT_NAME="$2";           shift 2 ;;
    --instance-type-arm64) INSTANCE_TYPE_ARM64="$2";   shift 2 ;;
    --instance-type-x86)   INSTANCE_TYPE_X86="$2";     shift 2 ;;
    --disk-size-gb)        DISK_SIZE_GB="$2";           shift 2 ;;
    --enable-nat-gateway)  ENABLE_NAT_GATEWAY="true";  shift 1 ;;
    --domain-name)         DOMAIN_NAME="$2";           shift 2 ;;
    --certificate-arn)     CERTIFICATE_ARN="$2";       shift 2 ;;
    --kubeconfig)          export KUBECONFIG="$2";      shift 2 ;;
    --k8s-version)         K8S_VERSION="$2";           shift 2 ;;
    --arch)                ARCH="$2";                  shift 2 ;;
    *)            break ;;
  esac
done

export CDK_DEFAULT_REGION="${REGION}"
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

case "$COMMAND" in
  deploy)
    cdk_bootstrap
    case "$STACK" in
      all)
        if [[ "$DEPLOYMENT_MODE" == "self-managed" ]]; then
          echo "==> Self-managed mode: skipping infra stack and AMI registration"
          deploy_control_plane
        else
          deploy_infra
          register_amis
          deploy_control_plane
        fi
        ;;
      infra)
        if [[ "$DEPLOYMENT_MODE" == "self-managed" ]]; then
          echo "ERROR: infra stack is not applicable in self-managed mode"; exit 1
        fi
        deploy_infra
        ;;
      control-plane)  deploy_control_plane ;;
      *) echo "Unknown stack: $STACK"; exit 1 ;;
    esac
    echo ""; echo "✓ Deployment complete (region=${REGION}, mode=${DEPLOYMENT_MODE})"
    ;;
  destroy)
    # Safety check: ensure no clusters are still registered
    if command -v "${SCRIPT_DIR}/bin/ecp" &>/dev/null || command -v ecp &>/dev/null; then
      ECP_BIN="${SCRIPT_DIR}/bin/ecp"
      [[ -x "$ECP_BIN" ]] || ECP_BIN="ecp"
      CLUSTERS=$("$ECP_BIN" list-clusters 2>/dev/null || true)
      if [[ -n "$CLUSTERS" ]] && ! echo "$CLUSTERS" | grep -qi "no clusters"; then
        echo "==> WARNING: Active clusters detected in this region:"
        echo ""
        echo "$CLUSTERS"
        echo ""
        echo "Destroying the platform with active clusters will leave orphaned EC2 instances,"
        echo "EBS volumes, and stale DynamoDB entries."
        echo ""
        echo "Please delete all clusters first:"
        echo "  ecp delete-cluster <name> --region ${REGION}"
        echo ""
        read -r -p "Continue anyway? (yes/no): " CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
          echo "Aborted."
          exit 1
        fi
      fi
    fi
    case "$STACK" in
      all)
        cd "${SCRIPT_DIR}/control-plane" && cdk destroy --app cdk.out --all --force --region "${REGION}" || true
        cd "${SCRIPT_DIR}/infra" && cdk destroy --app cdk.out --all --force --region "${REGION}" || true
        ;;
      infra)          cd "${SCRIPT_DIR}/infra" && cdk destroy --app cdk.out --all --force --region "${REGION}" ;;
      control-plane)  cd "${SCRIPT_DIR}/control-plane" && cdk destroy --app cdk.out --all --force --region "${REGION}" ;;
      *) echo "Unknown stack: $STACK"; exit 1 ;;
    esac
    echo "✓ Destroy complete"
    ;;
  register-amis)
    register_amis
    ;;
  install-charts)
    install_charts
    ;;
  verify-ami)
    exec "${SCRIPT_DIR}/bin/verify-ami.sh" \
      --sig-file "${SCRIPT_DIR}/ami-signatures.json" \
      --pubkey   "${SCRIPT_DIR}/express-compute-ami-signing.pub.pem" \
      "$@"
    ;;
  import-ami)
    exec "${SCRIPT_DIR}/bin/import-ami.sh" \
      --sig-file "${SCRIPT_DIR}/ami-signatures.json" \
      "$@"
    ;;
  ecp)
    exec "${SCRIPT_DIR}/bin/ecp" "$@"
    ;;
  *)
    echo "Unknown command: $COMMAND"
    usage
    ;;
esac
