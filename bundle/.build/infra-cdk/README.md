# EKS-D-Xpress Infra — Shared Infrastructure

Shared AWS infrastructure for the EKS-DX platform, deployed as a single AWS CDK stack. Provisions the VPC, EC2 launch templates, ECR pull-through cache, and S3 endpoint used by all EKS-DX tenants.

> Tenant control plane provisioning (EC2, IAM, SQS, cluster bootstrap) lives in a separate project.

## What This Deploys

- **VPC** `10.0.0.0/16` — IGW, NAT subnet, public + private route tables
- **S3 Gateway Endpoint** — keeps ECR pulls and Karpenter pricing data off NAT
- **ECR Pull-Through Cache** — `public.ecr.aws` and `registry.k8s.io` mirrored into your account ECR
- **4 EC2 Launch Templates** — (spot + on-demand) × (arm64 + x86_64), IMDS v2, encrypted EBS, no AMI ID
- **VPC Flow Logs** — CloudWatch, 1-week retention
- **SSM Parameters** — VPC ID + all 4 LT IDs published for consumers

## Usage

```bash
# Deploy
./setup-shared-infra.sh [region] [projectName]

# Destroy
./delete-shared-infra.sh [region] [projectName]
```

Defaults: `region=us-east-1`, `projectName=eks-dx-infra`.

## Prerequisites

- AWS CLI configured
- CDK CLI (`npm i -g aws-cdk`)
- Java 21 + Maven 3

## Configuration

All options can be customized in two ways:

1. **Edit `infra/cdk.json`** — changes the defaults permanently for all future deploys.
2. **Pass `--context` flags** at deploy time — overrides defaults without modifying files.

### Available Options

| Key | Default | Notes |
|-----|---------|-------|
| `projectName` | `eks-dx-infra` | Used in resource names and SSM paths |
| `instanceTypeArm64` | `c6g.xlarge` | Must support hibernation (spot LTs) |
| `instanceTypeX86_64` | `m7i.large` | Must support hibernation (spot LTs) |
| `diskSizeGb` | `20` | Root EBS volume size in GiB |
| `enableNatGateway` | `false` | Enable if workers need general internet egress |

### Overriding at Deploy Time

```bash
# Override instance types and enable NAT
cd infra
cdk deploy EksDxSharedInfraStack \
  --context instanceTypeArm64=m7g.xlarge \
  --context enableNatGateway=true \
  --require-approval never
```

Or using the convenience script (supports `projectName` and `region` only):

```bash
./setup-shared-infra.sh us-west-2 my-custom-project
```

For additional context overrides with the script, edit `infra/cdk.json` before running.

## SSM Outputs

| Path | Value |
|------|-------|
| `/eks-d-xpress/infra/network/vpc-id` | VPC ID |
| `/eks-d-xpress/infra/network/nat-gateway-enabled` | `true` or `false` |
| `/eks-d-xpress/infra/launch-template/{arch}/{spot\|ondemand}` | Launch template ID |

## Directory Structure

```
eks-d-xpress-infra/
├── setup-shared-infra.sh
├── delete-shared-infra.sh
├── infra/
│   ├── cdk.json
│   ├── pom.xml
│   └── src/main/java/cloud/plasticity/eksdx/
│       ├── EksDxApp.java
│       └── SharedInfraStack.java
└── archived/           # Legacy Terraform + eks-d-setup scripts
```
