# Express Compute Platform

Production-ready Kubernetes clusters with Karpenter autoscaling — deployed in under 4 minutes.

Express Compute runs on EC2 with a golden AMI strategy to eliminate runtime provisioning delays. Every component is pre-baked: binaries, container images, Helm charts, and system configuration. At boot time, the cluster simply starts what's already there.

Two Kubernetes distributions are supported, selected via `ecp create-cluster --distribution <eks-d|k3s>`:

| Distribution | Boot time | Best for |
|---|---|---|
| **EKS-D-Xpress** (default) | < 4 min | Full EKS API compatibility, etcd HA control planes |
| **k3s-Xpress** | < 4 min (~220s) | Dev/staging, edge, single-node, cost-sensitive workloads |

Both distributions share the same `ecp` CLI lifecycle, VPC CNI networking, Karpenter autoscaling, Workload Identity, and CloudWatch observability — all pre-baked into the golden AMI. See [k3s-Xpress](docs/user-guides/k3s-xpress.md) for the lightweight distribution's details and tradeoffs.

---

## Key Features

- **Sub-4-minute cluster boot** (both distributions — k3s-Xpress typically ~220s, EKS-D-Xpress up to 4 min) — all components pre-installed in the golden AMI
- **Two distributions** — EKS-D for full EKS API compatibility, or k3s for a lightweight footprint
- **EKS compatibility** — EKS-D-Xpress runs the same EKS-D binaries as Amazon EKS
- **Karpenter autoscaling** — Spot-first worker node provisioning with right-sizing
- **Multi-architecture** — ARM64 (Graviton) and x86_64 AMIs built in parallel
- **Cryptographic AMI signing** — KMS-backed attestation with offline verification
- **Workload Identity** — pod-level IAM without node-level over-provisioning
- **GitHub Actions CI/CD** — OIDC-authenticated Packer builds with zero static credentials
- **SBOM generation** — SPDX 2.3 Bill of Materials for every AMI release

---

## Quick Start

### Deploy a cluster (Docker bundle)

```bash
docker run --rm -it \
  --name express-compute-installer \
  -v ~/.aws:/root/.aws:ro \
  -e AWS_PROFILE="${AWS_PROFILE:-default}" \
  -e AWS_REGION="${AWS_REGION:-us-east-1}" \
  --entrypoint bash \
  ghcr.io/codriverlabs/express-compute-bundle:latest

# Inside the container:
./deploy.sh deploy --region us-east-1

# Create your first cluster (arm64, spot, ~4 min)
ecp create-cluster my-cluster \
  --distribution=eks-d \
  --arch=arm64 \
  --pricing=spot \
  --ssh-cidr "$(curl -s https://checkip.amazonaws.com/ | tr -d '\n')/32" \
  --wait
```

### Build a golden AMI locally

```bash
cd ami-builder
./build-golden-amis.sh
```

See the [Deployment Guide](docs/user-guides/deployment.md) for full instructions.

---

## Documentation

### User Guides

| Guide | Description |
|-------|-------------|
| [Deployment](docs/user-guides/deployment.md) | Deploy the platform end-to-end |
| [Self-Managed Quick Start](docs/user-guides/self-managed-quick-start.md) | Add Workload Identity to existing clusters (k3s, microk8s, EKS-D) |
| [ecp CLI Reference](docs/user-guides/ecp-cli/README.md) | CLI command reference |
| [Architecture](docs/user-guides/architecture.md) | System design and component relationships |
| [Components](docs/user-guides/components.md) | Component reference and configuration |
| [AMI Builder](docs/user-guides/ami-builder.md) | Build, sign, and manage golden AMIs |
| [Custom Golden AMIs](docs/user-guides/golden-ami-customization.md) | Customize AMIs for your environment |
| [GitHub Actions Pipeline](docs/user-guides/github-actions-pipeline.md) | CI/CD setup for automated AMI builds |
| [Cluster Setup](docs/user-guides/cluster-setup.md) | Boot sequence and cluster lifecycle |
| [Node Pools](docs/user-guides/node-pools.md) | Karpenter NodePool and EC2NodeClass configuration |
| [k3s-Xpress](docs/user-guides/k3s-xpress.md) | Lightweight k3s clusters with golden AMI strategy |

### Reference

| Document | Description |
|----------|-------------|
| [Component Versions](COMPONENT_VERSIONS.md) | Pinned EKS-D component version matrix |
| [k3s Component Versions](K3S_COMPONENT_VERSIONS.md) | Pinned k3s component version matrix |
| [AMI Pipeline Setup](docs/AMI_PIPELINE_SETUP.md) | One-time AWS account setup for AMI builds |
| [AMI Verification](docs/AMI_VERIFICATION.md) | Verify AMI signatures offline |
| [Deployment Bundle](docs/DEPLOYMENT_BUNDLE.md) | Bundle contents and build process |
| [Cost Estimation](cost-estimation.md) | Infrastructure cost breakdown |

### Design Documents

| Document | Description |
|----------|-------------|
| [AMI Builder Modularization](docs/design/ami-builder-modularization.md) | Component script architecture |
| [Workstation API](docs/design/workstation-api.md) | Control plane API design |
| [Shared Infra CDK Migration](docs/design/shared-infra-cdk-migration.md) | CDK infrastructure patterns |

---

## Repository Structure

```
express-compute-platform/
├── ami-builder/              # Golden AMI creation (Packer + scripts + CDK for IAM)
│   ├── cdk/                  #   Java CDK stack for GitHub OIDC IAM setup
│   ├── scripts/              #   AMI provisioning scripts and components
│   ├── ecp-golden-ami.pkr.hcl  # Packer template (dual-arch)
│   └── Makefile              #   Build orchestration
├── cluster-setup/            # Boot-time installation scripts (05–18)
│   ├── setup-eks-d.sh        #   Master orchestrator
│   └── manifests/            #   Kubernetes manifests for install steps
├── node-pools/               # Karpenter NodePool + EC2NodeClass configs
│   ├── chart/                #   Helm chart for runtime node pool deployment
│   └── configure-nodepools.sh  # Runtime configuration script
├── bundle/                   # Deployment bundle (Docker image + deploy.sh)
├── monitoring/               # CloudWatch agent configuration
├── docs/                     # All documentation
└── .github/workflows/        # CI/CD (release, bundle, ecr-credential-provider)
```

---

## Architecture at a Glance

```
┌─────────────────────────────────────────────────────────┐
│                    Express Compute                        │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────┐    ┌────────────────────────┐     │
│  │   Golden AMI      │    │   Deployment Bundle     │     │
│  │                   │    │                         │     │
│  │  EKS-D binaries   │    │  CDK stacks (synth'd)  │     │
│  │  Container images  │    │  Helm charts           │     │
│  │  Helm charts       │    │  deploy.sh CLI         │     │
│  │  System config     │    │  ecp CLI               │     │
│  └────────┬──────────┘    └───────────┬────────────┘     │
│           │                           │                  │
│           ▼                           ▼                  │
│  ┌──────────────────┐    ┌────────────────────────┐     │
│  │   EC2 Instance    │    │   AWS Infrastructure    │     │
│  │                   │    │                         │     │
│  │  setup-eks-d.sh   │    │  VPC + Subnets         │     │
│  │  ↓ 05→18 scripts  │    │  IAM Roles             │     │
│  │  ↓ ~4 min boot    │    │  SSM Parameters        │     │
│  │  ↓ Cluster ready  │    │  Launch Templates      │     │
│  └────────┬──────────┘    └────────────────────────┘     │
│           │                                              │
│           ▼                                              │
│  ┌──────────────────────────────────────────────┐       │
│  │            Running Cluster                     │       │
│  │                                                │       │
│  │  Control Plane (EKS-D) + Karpenter Workers     │       │
│  │  VPC CNI │ EBS CSI │ CloudWatch │ Metrics      │       │
│  └────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- AWS account with appropriate permissions
- Docker (for deployment bundle)
- For AMI builds: Packer 1.9+, AWS CLI, Make

---

## License

See [LICENSE.md](LICENSE.md).
