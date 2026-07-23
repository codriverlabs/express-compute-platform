# AMI Builder Guide

The AMI builder creates golden AMIs containing all software needed to boot an EKS-D cluster in under 3 minutes. It uses Packer to provision an EC2 instance, install everything, snapshot it, and optionally sign the result with a KMS key.

---

## How It Works

```
ami-builder/
├── ecp-golden-ami.pkr.hcl       # Packer template (x86_64 + arm64)
├── Makefile                      # Build orchestration
├── build-golden-amis.sh          # Interactive local build wrapper
├── cleanup-amis.sh               # Remove old AMIs from your account
├── scripts/
│   ├── install.sh                # Master provisioning orchestrator
│   ├── discover-eks-d.sh         # Resolves EKS-D release manifest versions
│   ├── component-versions.env    # Pinned add-on versions
│   ├── sign-ami.sh               # KMS-based cryptographic signing
│   ├── verify-ami.sh             # Offline signature verification
│   ├── import-ami.sh             # Copy + verify AMI into another account/region
│   ├── 00-configure-containerd.sh
│   ├── 01-install-base.sh
│   ├── 02-install-docker.sh
│   ├── 04-install-helm.sh
│   ├── extract-images.py         # Container image extraction helper
│   ├── build-with-version.sh     # Version-stamped build helper
│   └── components/               # Per-component image/chart pull scripts
│       ├── cert-manager.sh
│       ├── karpenter.sh
│       ├── ebs-csi.sh
│       ├── cloud-provider-aws.sh
│       ├── vpc-cni.sh
│       ├── cloudwatch.sh
│       ├── system-images.sh
│       └── ecp.sh
├── cdk/                          # Java CDK stack for GitHub OIDC IAM
├── files/                        # Pre-built binaries (ecr-credential-provider)
└── output/                       # Build artifacts (manifest, SBOMs)
```

### Build Phases

The Packer build executes in this order:

1. **File upload** — `cluster-setup/`, `scripts/`, `node-pools/`, and the `ecr-credential-provider` binary are copied to the builder instance.

2. **`install.sh` orchestration** — the master script runs:
   - Version discovery (EKS-D release manifest parsing)
   - Binary installation (kubeadm, kubelet, kubectl, syft, ecr-credential-provider)
   - System configuration (kubelet systemd unit, kernel params, ECR credential provider config)
   - Tool installation (base packages, Docker, Helm, containerd)
   - Component image/chart pulls (cert-manager, Karpenter, EBS CSI, VPC CNI, CloudWatch, etc.)
   - EKS-D control plane image pulls (apiserver, etcd, scheduler, controller-manager, coredns)
   - ecp-boot.service installation (systemd unit that runs `setup-eks-d.sh` at boot)

3. **SBOM generation** — syft scans the filesystem and produces an SPDX 2.3 JSON document.

4. **Post-processing** — AMI IDs are pushed to SSM parameters and a manifest JSON is written.

---

## Building AMIs Locally

### Prerequisites

- AWS CLI configured with credentials that can:
  - Launch EC2 instances
  - Create AMIs and snapshots
  - Write SSM parameters under `/express-compute/*`
  - Assume the `express-compute-packer-builder` instance profile (or run the CDK stack first)
- Packer 1.9+ (auto-installed by the Makefile if missing)
- Make
- The `express-compute-packer-ci` IAM role (deploy with `ami-builder/cdk/`)

### Interactive Build

```bash
cd ami-builder
./build-golden-amis.sh
```

This prompts for:
- AWS region (default: `us-east-1`)
- Kubernetes version (default: `1.35`)
- Architecture (default: `arm64`)
- Build type: `internal` (uses ECR pull-through cache) or `release` (direct upstream registries)

### Makefile Targets

```bash
# Full build: stage binaries → packer build → clean security groups → sign AMI
make -C ami-builder ami \
  AWS_REGION=us-east-1 \
  KUBERNETES_VERSION=1.35 \
  ARCH=arm64 \
  BUILD_TYPE=internal

# Individual targets:
make -C ami-builder stage           # Copy ecr-credential-provider to files/
make -C ami-builder build           # Run packer build
make -C ami-builder clean-sgs       # Remove leftover packer_* security groups
make -C ami-builder sign            # Sign the AMI attestation with KMS
```

### Build Types

| Type | Registry source | Use case |
|------|----------------|----------|
| `internal` | ECR pull-through cache (`<account>.dkr.ecr.<region>.amazonaws.com/<prefix>`) | Day-to-day builds, faster in-region pulls |
| `release` | Direct upstream (`public.ecr.aws`, `registry.k8s.io`, `quay.io`) | GitHub Actions release builds, no dependency on your ECR cache |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_REGION` | `us-east-1` | Target region for the AMI |
| `KUBERNETES_VERSION` | `1.35` | EKS-D Kubernetes minor version |
| `ARCH` | `arm64` | Architecture: `arm64` or `x86_64` |
| `BUILD_TYPE` | `internal` | Registry routing mode |
| `AMI_VERSION` | `YYYYMMDD-HHMM` | Version tag embedded in AMI name |

---

## What Gets Baked Into the AMI

### Binaries

| Binary | Source | Location |
|--------|--------|----------|
| kubeadm | EKS-D release manifest | `/usr/local/bin/kubeadm` |
| kubelet | EKS-D release manifest | `/usr/local/bin/kubelet` |
| kubectl | EKS-D release manifest | `/usr/local/bin/kubectl` |
| ecr-credential-provider | Built from source (Go) | `/usr/bin/ecr-credential-provider` |
| syft | GitHub releases | `/usr/local/bin/syft` |
| helm | Install script | `/usr/local/bin/helm` |
| docker | AL2023 package | system package |
| containerd | AL2023 package | system package |
| ecp | codriverlabs releases | `/usr/local/bin/ecp` (if `INSTALL_ECP=true`) |

### Container Images (pre-pulled into containerd)

- EKS-D control plane: apiserver, controller-manager, scheduler, etcd, coredns, kube-proxy, pause
- cert-manager (controller, webhook, cainjector)
- Karpenter (controller, webhook)
- EBS CSI driver + sidecars (attacher, provisioner, resizer, snapshotter, registrar, livenessprobe)
- AWS Cloud Controller Manager
- AWS VPC CNI (aws-node, init)
- CloudWatch agent
- Metrics Server
- Express Compute components (credential-service, management-service, karpenter-support)

### Configuration

- kubelet systemd service + kubeadm drop-in
- ECR credential provider config (`/etc/kubernetes/credential-provider/config.yaml`)
- Kernel networking (ip_forward, bridge-nf-call-iptables, overlay, br_netfilter)
- systemd-networkd ENI fix (prevents stealing secondary IPs from VPC CNI)
- `ecp-boot.service` — systemd unit that runs `setup-eks-d.sh` on first boot
- Swap disabled permanently

### Scripts Staged on the AMI

| Path | Purpose |
|------|---------|
| `/opt/cluster-setup/` | Boot-time install scripts (05–18) |
| `/opt/cluster-setup/charts/` | Pre-pulled Helm charts |
| `/opt/cluster-setup/karpenter/` | NodePool chart + configure script |
| `/opt/eks-d/manifests/` | EKS-D release manifest + version env |
| `/opt/eks-d/version.env` | Kubernetes + EKS-D version info |

---

## AMI Signing and Verification

Every release AMI is cryptographically signed using AWS KMS (RSA-4096).

### How Signing Works

1. After Packer builds the AMI, `sign-ami.sh` creates a JSON attestation:
   ```json
   {
     "ami_id": "ami-0abc123...",
     "arch": "arm64",
     "kubernetes_version": "1.35",
     "ami_version": "20260603-1445",
     "timestamp": "2026-06-03T14:45:00Z"
   }
   ```

2. Signs with `aws kms sign` (RSASSA_PKCS1_V1_5_SHA_256)

3. Stores the signature in `ami-signatures.json` (released as a GitHub artifact)

4. Tags the AMI: `Signed=true`, `SigningKeyArn=arn:aws:kms:...`

### Verifying an AMI (Offline)

No AWS credentials required — uses the bundled public key:

```bash
./ami-builder/scripts/verify-ami.sh \
  --ami-id ami-0abc1234def56789 \
  --sig-file ami-signatures.json \
  --pubkey express-compute-ami-signing.pub.pem
```

Output:
```
✓ Signature VALID — ami-0abc1234def56789 (arm64, k8s 1.35, version 20260603-1445)
```

### Importing an AMI to Another Account/Region

The `import-ami.sh` script verifies the signature first, then copies the AMI:

```bash
./ami-builder/scripts/import-ami.sh \
  --ami-id ami-0abc1234def56789 \
  --src-region us-east-1 \
  --regions us-west-2,eu-west-1,ap-southeast-1
```

This:
1. Verifies the AMI signature (fails fast if invalid)
2. Copies the AMI to each target region
3. Registers the new AMI ID in SSM (`/express-compute/infra/ami/{arch}/{version}`)

---

## Cleaning Up Old AMIs

```bash
./ami-builder/cleanup-amis.sh
```

This removes AMIs tagged with `Platform=express-compute` that are older than the retention period, along with their backing EBS snapshots.

---

## Component Versions

All add-on versions are pinned in `ami-builder/scripts/component-versions.env`:

```bash
ECP_CONTROL_PLANE_VERSION=1.0.0-rc4
INSTALL_ECP=true
CERT_MANAGER_VERSION=v1.20.2
KARPENTER_VERSION=1.13.0
SYFT_VERSION=1.22.0
```

Kubernetes and EKS-D versions are resolved dynamically from the upstream EKS-D release manifest by `discover-eks-d.sh`. See [COMPONENT_VERSIONS.md](../../COMPONENT_VERSIONS.md) for the full matrix.

---

## Troubleshooting

### Packer build fails at ECR login

The builder instance needs an instance profile with ECR pull permissions. Ensure the CDK stack has been deployed:

```bash
cd ami-builder/cdk && cdk deploy
```

### "ecr-credential-provider not found" during stage

The binary must exist at `cluster-setup/{arch}/ecr-credential-provider`. Build it first:

```bash
# Triggered automatically by the release workflow, or:
GOARCH=arm64 go build -o cluster-setup/arm64/ecr-credential-provider ./cmd/ecr-credential-provider
```

### Stale Packer security groups

If a build is interrupted, Packer may leave `packer_*` security groups behind:

```bash
make -C ami-builder clean-sgs AWS_REGION=us-east-1
```

### AMI build takes too long

Image pulls dominate build time. Use `BUILD_TYPE=internal` with an ECR pull-through cache for in-region pulls (~5-8 min vs ~12-15 min for `release`).

---

## Next Steps

- [Custom Golden AMIs](golden-ami-customization.md) — add your own software to the AMI
- [GitHub Actions Pipeline](github-actions-pipeline.md) — automate builds in CI
- [AMI Pipeline Setup](../AMI_PIPELINE_SETUP.md) — one-time AWS account setup
