# Express Compute Workload Identity Integration

Documents the integration points for Workload Identity across the platform:
- AMI bake-time pre-caching
- Boot-time installation (managed clusters)
- Standalone installation (self-managed clusters)

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  AMI Build Time (ami-builder/scripts/components/ecp.sh)          │
│                                                                   │
│  • ecp CLI binary → /usr/local/bin/ecp                           │
│  • Helm charts → /opt/cluster-setup/charts/                      │
│  • Container images → containerd image store                     │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│  Boot Time (cluster-setup/12-install-ecp-workload-identity.sh)   │
│                                                                   │
│  Guards: INSTALL_ECP=true AND ECP_ENDPOINT set                   │
│  Delegates to: cluster-setup/install-ecp-workload-identity.sh    │
│  Mode: --oidc-mode managed (cluster pre-registered by Lambda)    │
│  Charts: local from /opt/cluster-setup/charts/ (no network pull) │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│  Standalone (curl | bash for self-managed clusters)              │
│                                                                   │
│  Script: install-ecp-workload-identity.sh (published in release) │
│  Mode: --oidc-mode self-managed (registers cluster via ecp CLI)  │
│  Charts: pulled from GHCR OCI at runtime                         │
└──────────────────────────────────────────────────────────────────┘
```

---

## Scripts

### `cluster-setup/12-install-ecp-workload-identity.sh`

Thin wrapper invoked by `setup-eks-d.sh` at boot (step 12). Guards:

1. `INSTALL_ECP=true` (set in `/opt/eks-d/version.env` at AMI build time)
2. `ECP_ENDPOINT` is set (injected via user-data by provisioner Lambda)

If both pass, delegates to the canonical script with `--oidc-mode managed`.

### `cluster-setup/install-ecp-workload-identity.sh`

The canonical installer. Handles both managed and self-managed modes:

| Component | Managed (AMI boot) | Self-Managed (curl) |
|-----------|-------------------|---------------------|
| cert-manager | ✅ pre-installed (step 11) | ✅ installed if missing |
| Cluster registration | Skipped (Lambda did it) | ✅ `ecp create-cluster --jwks-file` |
| ecp-auth-proxy | ✅ from local charts | ✅ from GHCR OCI |
| ecp-workload-identity-webhook | ✅ from local charts | ✅ from GHCR OCI |
| eks-pod-identity-agent | ✅ from local charts + pre-pulled image | ✅ with ECR pull secret |

---

## AMI Builder Integration

### `ami-builder/scripts/install.sh`

- ✅ Validates `ECP_CONTROL_PLANE_VERSION` from `component-versions.env`
- ✅ Persists version to `/opt/eks-d/version.env`
- ✅ Downloads `ecp` CLI from GitHub release (arch-matched)

### `ami-builder/scripts/components/ecp.sh`

Gated by `INSTALL_ECP=true`. Pre-caches:

- ✅ Helm charts: `express-compute-auth-proxy`, `express-compute-workload-identity-webhook`, `express-compute-karpenter-support`
- ✅ Container images: `express-compute-auth-proxy`, `express-compute-workload-identity-webhook`
- ✅ `eks-pod-identity-agent` chart (from GitHub `aws/eks-pod-identity-agent`)
- ✅ `eks-pod-identity-agent` images (from ECR `602401143452`)

---

## Boot Sequence Position

```
11-install-cert-manager.sh         ← prerequisite (webhook TLS)
11b-install-kubelet-csr-approver.sh
12-install-ecp-workload-identity.sh ← THIS (conditional)
13-install-ebs-csi.sh
```

In `setup-eks-d.sh`:

```bash
if [[ "${INSTALL_ECP:-false}" == "true" && -n "${ECP_ENDPOINT:-}" ]]; then
  run_step 12 "Express Compute Workload Identity" "12-install-ecp-workload-identity.sh"
fi
```

---

## Environment Variables

### At AMI build time (`component-versions.env`)

| Variable | Example | Purpose |
|----------|---------|---------|
| `ECP_CONTROL_PLANE_VERSION` | `1.0.0-rc11` | Version for CLI + charts |
| `INSTALL_ECP` | `true` | Gate for ECP component caching |
| `ECP_GHCR_REGISTRY` | `ghcr.io/codriverlabs` | OCI registry for charts + images |

### At boot time (`/opt/eks-d/cluster.env`, injected by Lambda)

| Variable | Example | Purpose |
|----------|---------|---------|
| `ECP_ENDPOINT` | `https://ecp.codriverlabs.ai` | Control plane API |
| `CLUSTER_NAME` | `alice-ecp-arm64` | Cluster identifier |
| `AWS_REGION` | `us-east-1` | AWS region |
| `TENANT_ID` | `alice` | Tenant identifier |

### At standalone install time (user-set)

| Variable | Required | Purpose |
|----------|----------|---------|
| `CLUSTER_NAME` | Yes | Cluster identifier |
| `AWS_REGION` | Yes | AWS region |
| `ECP_CONTROL_PLANE_VERSION` | Yes | Chart/image version to pull |
| `ECP_ENDPOINT` | No | Auto-resolved from SSM if not set |
| `CHART_DIR` | No | Override local chart path |

---

## IAM Permissions

### Managed clusters (instance profile)

The provisioner Lambda attaches these to the instance role:

| Action | Resource | Purpose |
|--------|----------|---------|
| `ssm:GetParameter` | `/express-compute/*` | Resolve endpoint |
| `ecr:GetAuthorizationToken` | `*` | Pull eks-pod-identity-agent |
| `ecr:BatchGetImage` | `602401143452.dkr.ecr.*.amazonaws.com/*` | Pull agent image |

### Self-managed clusters (user credentials)

The user running the installer needs:

| Action | Resource | Purpose |
|--------|----------|---------|
| `ssm:GetParameter` | `/express-compute/control-plane/api/endpoint` | Resolve endpoint |
| `execute-api:Invoke` | Control plane API Gateway | Register cluster |
| `ecr:GetAuthorizationToken` | `*` | Pull eks-pod-identity-agent |

---

## Release Assets

Published in every `express-compute-platform` release:

| File | Purpose |
|------|---------|
| `install-ecp-workload-identity.sh` | Standalone installer for self-managed clusters |
| `install-ecp-workload-identity.sh.sha256` | SHA256 checksum for verification |
| `checksums.txt` | Combined checksums for all release artifacts |

Download and verify:

```bash
VERSION="1.0.0-rc11"
BASE="https://github.com/codriverlabs/express-compute-platform/releases/download/v${VERSION}"

curl -fsSL "${BASE}/install-ecp-workload-identity.sh" -o install-ecp-workload-identity.sh
curl -fsSL "${BASE}/install-ecp-workload-identity.sh.sha256" -o install-ecp-workload-identity.sh.sha256
sha256sum --check install-ecp-workload-identity.sh.sha256
chmod +x install-ecp-workload-identity.sh
```
