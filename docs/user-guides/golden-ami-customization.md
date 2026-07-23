# Custom Golden AMIs

This guide explains how to customize the Express Compute golden AMI — adding your own packages, tools, container images, or configuration on top of the standard build.

---

## Overview

The golden AMI is built by Packer using `ami-builder/ecp-golden-ami.pkr.hcl`. Customization happens by:

1. **Adding component scripts** — drop a new script in `ami-builder/scripts/components/`
2. **Modifying the install orchestrator** — add steps to `ami-builder/scripts/install.sh`
3. **Adding files** — place binaries or configs in `ami-builder/files/`
4. **Extending the Packer template** — add provisioners for complex cases

The approach you choose depends on what you're adding.

---

## Method 1: Component Scripts (Recommended)

The cleanest way to add software is a component script. These are sourced after ECR authentication is configured, so they have access to container registries.

### Create a Component Script

Create `ami-builder/scripts/components/my-tool.sh`:

```bash
#!/bin/bash
# my-tool.sh — pre-pull my-tool container image and chart
set -e
source /tmp/ami-build.env

echo "  → Pulling my-tool image..."
MY_TOOL_VERSION="1.2.3"
sudo ctr -n k8s.io images pull \
  --user "${ECR_CTR_USER}" \
  "${PUBLIC_ECR_CACHE}/my-org/my-tool:v${MY_TOOL_VERSION}"

echo "  → Pulling my-tool Helm chart..."
helm pull oci://${ECR_REGISTRY}/helm-charts/my-tool \
  --version "${MY_TOOL_VERSION}" \
  --destination /opt/cluster-setup/charts/
echo "  ✓ my-tool staged"
```

### Register It in install.sh

Add your component to the loop in `ami-builder/scripts/install.sh`:

```bash
for component in \
    cert-manager \
    karpenter \
    ebs-csi \
    cloud-provider-aws \
    vpc-cni \
    cloudwatch \
    system-images \
    ecp \
    my-tool; do        # ← add here
  echo "==> Component: ${component}"
  bash "${COMPONENTS_DIR}/${component}.sh"
done
```

### Available Variables in Component Scripts

All component scripts can `source /tmp/ami-build.env` which provides:

| Variable | Description | Example |
|----------|-------------|---------|
| `BUILD_TYPE` | `internal` or `release` | `internal` |
| `ECR_REGISTRY` | Your account's ECR endpoint | `123456789012.dkr.ecr.us-east-1.amazonaws.com` |
| `PUBLIC_ECR_CACHE` | Route to public.ecr.aws (direct or via cache) | `123456789012.dkr.ecr.us-east-1.amazonaws.com/public-ecr` |
| `K8S_REGISTRY_CACHE` | Route to registry.k8s.io | `123456789012.dkr.ecr.us-east-1.amazonaws.com/registry-k8s-io` |
| `QUAY_CACHE` | Route to quay.io | `123456789012.dkr.ecr.us-east-1.amazonaws.com/quay-io` |
| `ECR_CTR_USER` | `AWS:<password>` for containerd pulls | `AWS:eyJwYXlsb2...` |
| `REGION` | AWS region of the build | `us-east-1` |
| `ACCOUNT_ID` | AWS account ID | `123456789012` |

---

## Method 2: Adding System Packages

For OS-level packages, modify `ami-builder/scripts/01-install-base.sh` or create a new numbered script:

```bash
#!/bin/bash
# ami-builder/scripts/03-install-custom-packages.sh
set -e

echo "==> Installing custom packages..."
sudo dnf install -y \
  jq \
  htop \
  strace \
  tcpdump
echo "✓ Custom packages installed"
```

Then add a call to it in `install.sh` in the "Tool installation" section:

```bash
# ── 4. Tool installation ──────────────────────────────────────────────────────
echo "==> Installing base system..."
bash "${SCRIPT_DIR}/01-install-base.sh"
echo "==> Installing Docker..."
bash "${SCRIPT_DIR}/02-install-docker.sh"
echo "==> Installing custom packages..."
bash "${SCRIPT_DIR}/03-install-custom-packages.sh"    # ← add here
```

---

## Method 3: Pre-staging Binaries

For binaries that need to be on the AMI (not in a container), place them in `ami-builder/files/` and use a Packer file provisioner.

### Add the Binary to `files/`

```
ami-builder/files/
├── ecr-credential-provider-arm64
├── ecr-credential-provider-amd64
└── my-custom-binary              # ← your binary
```

### Upload in Packer

Add a provisioner block to `ecp-golden-ami.pkr.hcl`:

```hcl
provisioner "file" {
  source      = "${path.root}/files/my-custom-binary"
  destination = "/tmp/my-custom-binary"
}

provisioner "shell" {
  inline = [
    "sudo install -o root -g root -m 0755 /tmp/my-custom-binary /usr/local/bin/my-custom-binary"
  ]
}
```

---

## Method 4: Adding a Boot-time Install Step

If your customization requires a Kubernetes cluster to be running (e.g., deploying a CRD or Helm chart at boot), add a numbered script to `cluster-setup/`:

### Create the Script

```bash
#!/bin/bash
# cluster-setup/19-install-my-operator.sh
set -e

echo "Installing my-operator..."
helm upgrade --install my-operator \
  /opt/cluster-setup/charts/my-operator-*.tgz \
  --namespace my-operator \
  --create-namespace \
  --wait --timeout 60s

echo "✓ my-operator installed"
```

### Register in setup-eks-d.sh

Add a call at the appropriate point in `cluster-setup/setup-eks-d.sh`:

```bash
# After step 18 (or wherever appropriate in the sequence)
echo "Step 19: Installing my-operator..."
bash "${SCRIPT_DIR}/19-install-my-operator.sh"
update_progress "provisioning" "my-operator installed" 99
```

### Pre-pull the Chart

Add a component script (Method 1) that downloads the Helm chart into `/opt/cluster-setup/charts/` at AMI build time so it's available at boot without network access.

---

## Method 5: Custom Packer Template (Fork)

For large-scale customizations, you can create a separate Packer template that builds on top of the Express Compute AMI:

```hcl
# custom-ami.pkr.hcl
source "amazon-ebs" "custom" {
  region        = var.aws_region
  instance_type = "c6g.large"

  source_ami_filter {
    filters = {
      name = "express-compute-arm64-*"
      tag:Platform = "express-compute"
    }
    owners      = ["self"]
    most_recent = true
  }

  ami_name     = "my-org-custom-${var.version}"
  ssh_username = "ec2-user"

  tags = {
    BaseAMI  = "express-compute"
    Platform = "my-org"
  }
}

build {
  sources = ["source.amazon-ebs.custom"]

  provisioner "shell" {
    scripts = [
      "scripts/install-my-stuff.sh"
    ]
  }
}
```

This approach uses the Express Compute golden AMI as the base and layers your customizations on top.

---

## Customization Checklist

| Task | Where to modify | Example |
|------|-----------------|---------|
| Pre-pull a container image | `scripts/components/my-tool.sh` | Application images needed at boot |
| Pre-pull a Helm chart | `scripts/components/my-tool.sh` | Charts deployed during cluster setup |
| Install an OS package | `scripts/01-install-base.sh` or new script | `jq`, `htop`, observability agents |
| Add a static binary | `files/` + Packer provisioner | Custom CLI tools |
| Add a boot-time K8s step | `cluster-setup/XX-my-step.sh` + register in `setup-eks-d.sh` | Custom operator deployment |
| Change Kubernetes version | `KUBERNETES_VERSION` env var | Switch from 1.35 to 1.36 |
| Change add-on versions | `scripts/component-versions.env` | Bump cert-manager, Karpenter |
| Change instance type for build | `ecp-golden-ami.pkr.hcl` source blocks | Use bigger instance for faster builds |
| Change base OS | `source_ami_filter` in HCL | Different AL2023 variant |

---

## Testing Your Custom AMI

### 1. Build with Your Changes

```bash
make -C ami-builder ami \
  AWS_REGION=us-east-1 \
  KUBERNETES_VERSION=1.35 \
  ARCH=arm64 \
  BUILD_TYPE=internal \
  AMI_VERSION="custom-$(date +%Y%m%d-%H%M)"
```

### 2. Launch a Test Instance

```bash
AMI_ID=$(aws ssm get-parameter \
  --name /express-compute/infra/ami/arm64/1.35 \
  --query Parameter.Value --output text)

aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type c6g.large \
  --subnet-id subnet-xxx \
  --key-name my-key \
  --iam-instance-profile Name=express-compute-packer-builder \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ami-test}]'
```

### 3. Manually Boot a Cluster

SSH into the instance and run:

```bash
sudo mkdir -p /opt/eks-d
sudo tee /opt/eks-d/cluster.env <<EOF
TENANT_ID=test
CLUSTER_NAME=test-custom-ami
NODE_IP=$(hostname -I | awk '{print $1}')
AWS_REGION=us-east-1
EOF

sudo bash /opt/cluster-setup/setup-eks-d.sh
```

### 4. Verify Your Customization

```bash
# Check your binary exists
which my-custom-binary

# Check your images are pre-pulled
sudo ctr -n k8s.io images list | grep my-tool

# Check your chart is staged
ls /opt/cluster-setup/charts/my-tool-*
```

---

## Best Practices

1. **Keep component scripts idempotent** — they should succeed even if run twice.

2. **Pin versions explicitly** — never use `latest` tags. Add version pins to `component-versions.env`.

3. **Use the ECR pull-through cache** — for internal builds, images are cached in your account's ECR, making subsequent builds faster and avoiding rate limits.

4. **Test incrementally** — build with `BUILD_TYPE=internal` locally before committing to the release pipeline.

5. **Document your additions** — update `COMPONENT_VERSIONS.md` if you add new components, and add notes to the boot sequence section if you add cluster-setup steps.

6. **Respect the boot time budget** — the goal is sub-3-minute boot. Pre-pull everything possible at AMI build time. Network-dependent operations at boot time are the primary risk.

---

## Next Steps

- [AMI Builder](ami-builder.md) — full reference for the build system
- [GitHub Actions Pipeline](github-actions-pipeline.md) — automate your custom builds
- [Cluster Setup](cluster-setup.md) — understand the boot sequence
