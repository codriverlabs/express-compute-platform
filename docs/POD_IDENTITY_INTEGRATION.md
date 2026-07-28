# Express Compute Workload Identity Integration — Requirements

## Current State

- ✅ `cluster-setup/12-install-ecp-workload-identity.sh` — script exists, handles:
  - JWKS extraction from running cluster
  - Cluster registration with Express Compute control plane (`ecp register-cluster`)
  - Helm install of `ecp-auth-proxy`
  - Helm install of `ecp-workload-identity-webhook`
  - Graceful skip if `ECP_ENDPOINT` not set

- ✅ Wired into `setup-eks-d.sh` as step 6c (runs after cert-manager, skipped in dev mode
  when `ECP_ENDPOINT` is not set)
- ❌ Helm charts not pre-pulled in AMI builder
- ❌ Container images not pre-pulled in AMI builder
- ❌ `ecp` CLI binary not installed in AMI

## AMI Builder Requirements

Add to `ami-builder/scripts/install.sh`:

```bash
# Pre-pull Express Compute Workload Identity charts (from private ECR or bundled artifact)
echo "==> Pre-pulling Express Compute Workload Identity charts..."
# Source TBD — either private ECR OCI registry or S3 artifact
# helm pull oci://<registry>/ecp-auth-proxy --destination /tmp
# helm pull oci://<registry>/ecp-workload-identity-webhook --destination /tmp

# Install ecp CLI
echo "==> Installing ecp CLI..."
# Source TBD — S3 artifact or GitHub release
# curl -sL <url> -o /usr/local/bin/ecp && chmod +x /usr/local/bin/ecp

# Pre-pull container images for ecp-auth-proxy and ecp-workload-identity-webhook
# sudo ctr -n k8s.io images pull <registry>/ecp-auth-proxy:<tag>
# sudo ctr -n k8s.io images pull <registry>/ecp-workload-identity-webhook:<tag>
```

### Artifacts needed from ecp-control-plane repo:
1. `ecp` CLI binary (arm64 + x86_64)
2. `ecp-auth-proxy` Helm chart tarball
3. `ecp-workload-identity-webhook` Helm chart tarball
4. Container images for both components

## Boot Sequence Integration

In `setup-eks-d.sh`, add after CloudWatch (step 10) as an optional step:

```bash
# Step 11 (optional): Express Compute Workload Identity integration
# Only runs if ECP_ENDPOINT is set (provisioned by Lambda, not manual dev setup)
if [ -n "${ECP_ENDPOINT:-}" ]; then
  echo "Step 11: Registering with Express Compute control plane..."
  update_progress "registering" "Registering cluster with Express Compute" 97
  bash "${SCRIPT_DIR}/14-install-ecp-workload-identity.sh"
fi
```

## Progress Reporting

With the modular plugin architecture, this step belongs in a new group:

```
addons/
├── identity/                    # Pod identity & auth
│   └── ecp-workload-identity.sh   # Registers cluster + installs webhook
```

Progress mapping when integrated:
| Phase | Progress | Description |
|-------|----------|-------------|
| Core complete | 65% | Node ready, cert-manager installed |
| Addons (parallel) | 70-95% | storage + orchestration + telemetry |
| Express Compute registration | 97% | Cluster registered, webhooks installed |
| Ready | 100% | All components running |

Note: Express Compute registration should run AFTER cert-manager (needs webhook TLS certs)
and AFTER the cluster is fully functional. It's the last step before `ready`.

## Environment Variables

Passed via EC2 user-data (set by provisioner Lambda):

```bash
ECP_ENDPOINT=https://<function-url>.lambda-url.us-east-1.on.aws
ECP_API_URL=https://<api-id>.execute-api.us-east-1.amazonaws.com/prod
ECP_TENANTS_TABLE=ecp-tenants
```

For dev/manual provisioning (current `provision-tenant.sh`), these are not set
and the script gracefully skips — no Workload Identity integration in dev mode.

## IAM Permissions

The instance profile role needs (added by provisioner Lambda, not Terraform):

| Action | Resource | Purpose |
|--------|----------|---------|
| `lambda:InvokeFunctionUrl` | Express Compute Lambda | Cluster registration |
| `execute-api:Invoke` | Express Compute API Gateway | In-cluster component auth |

## User-Data Changes

When provisioned by Lambda (not Terraform), user-data includes additional env vars:

```bash
#!/bin/bash
mkdir -p /opt/eks-d
cat > /opt/eks-d/cluster.env <<CONF
TENANT_ID="<tenant-id>"
CLUSTER_NAME="<cluster-name>"
ECP_ENDPOINT="<lambda-function-url>"
ECP_API_URL="<api-gateway-url>"
ECP_TENANTS_TABLE="ecp-tenants"
CONF
```

The boot script sources `cluster.env` and the presence of `ECP_ENDPOINT`
triggers the Workload Identity integration step.
