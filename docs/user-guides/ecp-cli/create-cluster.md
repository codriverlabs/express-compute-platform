# ecp create-cluster

Create a managed cluster or register a self-managed one.

## Usage

```
ecp create-cluster [OPTIONS] <name>
```

## Arguments

| Argument | Description |
|----------|-------------|
| `<name>` | Cluster name (required) |

## Options

| Option | Description |
|--------|-------------|
| `--arch=<arch>` | CPU architecture: `arm64` or `x86_64` |
| `--disk-size=<diskSizeGb>` | Root disk size in GB |
| `--eip` | Assign Elastic IP |
| `--issuer=<issuer>` | SA token issuer URL (required with `--jwks-uri`/`--jwks-file`) |
| `--jwks-file=<jwksFile>` | Path to JWKS JSON file (triggers self-managed mode) |
| `--jwks-uri=<jwksUri>` | JWKS endpoint URL (triggers self-managed mode) |
| `--k8s-version=<k8sVersion>` | Kubernetes version |
| `--kubeconfig=<kubeconfig>` | Path to kubeconfig for JWKS/issuer discovery |
| `--output=<output>` | Output format: `text` or `json` |
| `--pricing=<ec2PricingModel>` | EC2 pricing: `spot` or `ondemand` |
| `--region=<region>` | AWS region |
| `--ssh-cidr=<sshCidr>` | CIDR for SSH access (restricts security group) |
| `--wait` | Stream progress and wait for completion |

## Modes

### Managed Cluster (default)

Provisions an EC2 instance with a golden AMI, boots EKS-D, and registers
with the control plane. This is the default when no `--jwks-*` or `--kubeconfig`
options are provided.

### Self-Managed Cluster

Registers an existing cluster (k3s, microk8s, EKS-D) for Workload Identity.
Triggered by providing `--jwks-file`, `--jwks-uri`, or `--kubeconfig`.

## Examples

```bash
# Managed cluster — arm64, spot, SSH locked to your IP, wait for ready
ecp create-cluster my-cluster \
  --arch=arm64 \
  --pricing=spot \
  --ssh-cidr "$(curl -s https://checkip.amazonaws.com/)/32" \
  --wait

# Managed cluster — x86_64, on-demand, with Elastic IP
ecp create-cluster prod-cluster \
  --arch=x86_64 \
  --pricing=ondemand \
  --eip \
  --disk-size=50 \
  --region us-east-1 \
  --wait

# Self-managed — register existing k3s cluster via kubeconfig
ecp create-cluster my-k3s \
  --kubeconfig ~/.kube/k3s-config

# Self-managed — register with explicit JWKS
ecp create-cluster external-cluster \
  --issuer https://my-cluster.example.com \
  --jwks-uri https://my-cluster.example.com/.well-known/openid-configuration/jwks
```
