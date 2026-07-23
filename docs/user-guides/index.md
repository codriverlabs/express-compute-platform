# User Guides

Comprehensive documentation for the Express Compute Platform.

---

## Getting Started

| Guide | Description |
|-------|-------------|
| [Deployment](deployment.md) | Deploy the platform end-to-end using the Docker bundle |
| [Architecture](architecture.md) | System architecture, components, and design decisions |

## Building AMIs

| Guide | Description |
|-------|-------------|
| [AMI Builder](ami-builder.md) | Build, sign, and manage golden AMIs (local and CI) |
| [Custom Golden AMIs](golden-ami-customization.md) | Extend the AMI with your own software, images, and scripts |
| [GitHub Actions Pipeline](github-actions-pipeline.md) | Automated CI/CD for AMI builds with OIDC authentication |

## Running Clusters

| Guide | Description |
|-------|-------------|
| [Cluster Setup](cluster-setup.md) | Boot sequence, lifecycle, and dev/manual mode |
| [Node Pools](node-pools.md) | Karpenter NodePool and EC2NodeClass configuration |
| [Components](components.md) | Component reference — what's installed and where |

---

## Quick Links

- [Component Versions](../../COMPONENT_VERSIONS.md) — pinned EKS-D version matrix
- [Cost Estimation](../../cost-estimation.md) — infrastructure cost breakdown
- [AMI Pipeline Setup](../AMI_PIPELINE_SETUP.md) — one-time AWS account configuration
- [AMI Verification](../AMI_VERIFICATION.md) — verify AMI signatures offline
- [Deployment Bundle](../DEPLOYMENT_BUNDLE.md) — bundle contents and build process

---

## Prerequisites

Before using these guides, ensure you have:

- AWS account with appropriate IAM permissions
- AWS CLI configured (`aws sts get-caller-identity` succeeds)
- Docker installed (for the deployment bundle)
- For AMI builds: Packer 1.9+, Make, and the CDK-provisioned IAM role
- Basic understanding of Kubernetes concepts
