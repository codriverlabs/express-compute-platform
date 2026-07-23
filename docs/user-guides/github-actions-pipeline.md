# GitHub Actions Pipeline

This guide covers the CI/CD pipeline that automatically builds, signs, and releases golden AMIs when you push a version tag to GitHub.

---

## Pipeline Overview

```
Tag push (v*)  ──→  build-ecr-credential-provider  ──→  build-ami (matrix)  ──→  release
                         │                                    │
                         │  Go cross-compile arm64 + amd64    │  Packer build per arch
                         │  Upload artifacts                  │  Sign with KMS
                         ▼                                    │  Upload SBOM
                    ecr-credential-provider-arm64              ▼
                    ecr-credential-provider-amd64         ami-manifest.json
                                                         ami-signatures.json
                                                         sbom-*.spdx.json
                                                         ──→ GitHub Release
```

### Workflow Files

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `.github/workflows/release.yml` | Tag `v*` or `workflow_dispatch` | Full release: build binaries → build AMIs → create GitHub release |
| `.github/workflows/build-ecr-credential-provider.yml` | Called by `release.yml` | Cross-compile the ECR credential provider binary |
| `.github/workflows/bundle-release.yml` | `workflow_dispatch` only | Build and push the deployment Docker bundle to GHCR |

---

## Prerequisites

### One-time AWS Setup

Before the pipeline can run, you need IAM infrastructure in your AWS account:

```bash
cd ami-builder/cdk
cdk deploy ExpressComputePackerIamGithubStack \
  -c githubOrg=codriverlabs \
  -c githubOrgId=236268168 \
  -c githubRepo=express-compute-platform \
  -c githubRepoId=1250509430
```

This creates:
- **IAM OIDC Provider** — trusts GitHub-issued JWT tokens
- **IAM Role** (`express-compute-packer-ci`) — assumed by GitHub Actions via OIDC
- **KMS Key** (`alias/express-compute-ami-signing`) — RSA-4096 for AMI attestation
- **SSM Parameter** — stores the KMS key ARN for pipeline reference

See [AMI Pipeline Setup](../AMI_PIPELINE_SETUP.md) for the detailed walkthrough.

### GitHub Repository Configuration

Add these in your repository's Settings → Secrets and variables:

| Type | Name | Value |
|------|------|-------|
| Secret | `AWS_PACKER_ROLE_ARN` | `arn:aws:iam::<account>:role/express-compute-packer-ci` |
| Variable | `AWS_REGION` | `us-east-1` (or your build region) |

No static AWS credentials are stored — authentication uses OIDC.

---

## How OIDC Authentication Works

```
GitHub Actions Runner                     AWS
─────────────────────                     ───
1. Workflow starts with
   `permissions: id-token: write`
   
2. Runner requests OIDC token from
   GitHub's token endpoint
   
3. GitHub issues JWT with claims:
   - iss: token.actions.githubusercontent.com
   - aud: sts.amazonaws.com
   - sub: repo:codriverlabs/express-compute-platform:ref:refs/tags/v1.0.0
   
4. aws-actions/configure-aws-credentials
   calls STS AssumeRoleWithWebIdentity      → STS validates JWT signature
                                            → Checks trust policy conditions
                                            → Issues temporary credentials
                                              (valid ~1 hour)
   
5. Packer uses temporary credentials
   to build AMIs
```

The trust policy on the IAM role restricts access to:
- **Audience**: `sts.amazonaws.com`
- **Subject**: `repo:codriverlabs/express-compute-platform:*` (any branch/tag)

For production accounts, narrow to specific refs:
```json
"StringEquals": {
  "token.actions.githubusercontent.com:sub":
    "repo:codriverlabs/express-compute-platform:ref:refs/heads/main"
}
```

---

## Release Workflow in Detail

### Triggering a Release

**Automatic (tag push):**
```bash
git tag v1.0.0-rc1
git push origin v1.0.0-rc1
```

**Manual (workflow_dispatch):**
Go to Actions → Release → Run workflow. Parameters:
- `k8s_versions`: Comma-separated versions to build (default: `1.35,1.36`)
- `build_ami`: Whether to run the Packer build (default: `true`)

### Job 1: build-ecr-credential-provider

Cross-compiles the ECR credential provider Go binary for both architectures:

```yaml
strategy:
  matrix:
    arch: [arm64, amd64]
    k8s_version: ['1.35', '1.36']
```

Outputs uploaded as artifacts:
- `ecr-credential-provider-arm64`
- `ecr-credential-provider-amd64`

### Job 2: build-ami

Runs after Job 1 completes. Matrix strategy:

```yaml
strategy:
  matrix:
    k8s_version: ['1.35']
    arch: ['arm64', 'x86_64']
```

Steps:
1. **Checkout** — gets the repository code
2. **Download artifacts** — retrieves ecr-credential-provider binaries from Job 1
3. **Configure AWS credentials** — OIDC authentication
4. **Build AMI** — runs `make -C ami-builder build` with `BUILD_TYPE=release`
5. **Sign AMI** — runs `make -C ami-builder sign`
6. **Upload SBOM** — stores SPDX JSON as a build artifact

### Job 3: release

Runs after all AMI builds complete. Only executes for tag pushes (`startsWith(github.ref, 'refs/tags/')`).

Creates a GitHub Release with:
- `ami-manifest.json` — nested `{version: {arch: {region: ami_id}}}` mapping
- `ami-signatures.json` — per-AMI cryptographic attestation signatures
- `ecr-credential-provider-arm64` / `ecr-credential-provider-amd64`
- `sbom-*.spdx.json` — SBOM for each architecture
- `verify-ami.sh` — standalone verification script
- `import-ami.sh` — cross-account AMI import script
- `express-compute-ami-signing.pub.pem` — public key for offline verification
- `install-ecp-workload-identity.sh` — standalone installer for existing clusters
- `checksums.txt` — SHA-256 checksums of all release assets

---

## Modifying the Pipeline

### Adding a New Kubernetes Version

1. Update the matrix in `release.yml`:
   ```yaml
   matrix:
     k8s_version: ['1.35', '1.36']  # ← add new version
     arch: ['arm64', 'x86_64']
   ```

2. Verify the EKS-D release manifest exists:
   ```bash
   curl -sf https://distro.eks.amazonaws.com/kubernetes-1-36/kubernetes-1-36-eks-2.yaml > /dev/null && echo OK
   ```

3. Update `COMPONENT_VERSIONS.md` with the new version's components.

### Adding a Build Step

Add steps between "Build AMI" and "Sign AMI" in `release.yml`:

```yaml
- name: Run custom validation
  run: |
    # Your validation logic here
    AMI_ID=$(jq -r '.[0].ami_id' ami-builder/output/ami-manifest-entries.json)
    echo "Validating AMI: $AMI_ID"
```

### Changing the Build Region

Update the `AWS_REGION` variable in GitHub repository settings. The pipeline builds in one region; use `import-ami.sh` to replicate to others.

### Running Only the Credential Provider Build

Trigger `build-ecr-credential-provider.yml` separately via `workflow_dispatch` from the release workflow, or extract it as a standalone workflow.

---

## Security Model

### Permissions Granted to the CI Role

| Service | Scope | Purpose |
|---------|-------|---------|
| EC2 | Instance lifecycle, AMIs, snapshots, SGs, key pairs | Packer builds |
| EC2 (destructive) | Only resources tagged `ManagedBy=Packer` | Cleanup after build |
| EC2 RunInstances | Limited to `c6a.large` and `c6g.large` | Prevent instance abuse |
| IAM | `packer-*` resource prefix only | Temporary instance profiles |
| SSM | `/express-compute/*` parameters only | AMI ID + signature storage |
| KMS | Keys tagged `Usage=express-compute-ami-signing` | AMI attestation signing |
| ECR | Read-only (`GetAuthorizationToken`, `BatchGetImage`) | Pull container images |

### Permissions Boundary

Any IAM role Packer creates (temporary instance profiles) must include the `express-compute-packer-boundary` permissions boundary. This prevents privilege escalation — even if Packer creates a role, it cannot exceed the boundary.

### Builder Instance Profile

The temporary EC2 instance (the one being provisioned) only gets:
- ECR pull-through cache read access
- SSM `GetParameter` for `/express-compute/*`
- `sts:GetCallerIdentity`

It has **no write access** to any AWS service.

---

## Troubleshooting

### "Could not assume role" Error

```
Error: Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

**Causes:**
- The GitHub org ID or repo ID in the CDK context doesn't match
- The trust policy restricts to a different branch/tag pattern
- The `AWS_PACKER_ROLE_ARN` secret is incorrect

**Fix:** Verify the OIDC subject claim matches your trust policy:
```bash
# In your workflow, add a debug step:
- run: |
    curl -sH "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq .value | cut -d. -f2 | base64 -d | jq .sub
```

### Packer Timeout

**Symptom:** Build hangs for 30+ minutes then fails.

**Causes:**
- No public IP assigned (can't reach package repos)
- Security group blocks outbound
- Instance profile doesn't have ECR access

**Fix:** Check the Packer log:
```bash
# Locally:
cat packer-build-*.log | grep -i error

# In CI: download the log artifact or check the workflow run output
```

### AMI Not Found After Build

**Symptom:** `aws ssm get-parameter --name /express-compute/infra/ami/arm64/1.35` returns nothing.

**Cause:** The post-processor that writes to SSM may have failed silently.

**Fix:** Check `ami-builder/output/packer-manifest.json` for the AMI ID, then manually store it:
```bash
aws ssm put-parameter \
  --name /express-compute/infra/ami/arm64/1.35 \
  --value ami-0abc123 \
  --type String --overwrite
```

### Tag Creation Blocked

```
remote: error: GH013: Repository rule violations found
```

The `v_release_tagging` ruleset restricts tag creation. Only repo admins can bypass. Ensure you have admin access or ask an admin to push the tag.

---

## Pipeline Execution Times

| Job | Typical Duration | Bottleneck |
|-----|-----------------|------------|
| build-ecr-credential-provider | 2-4 min | Go cross-compile |
| build-ami (per arch) | 10-15 min | Container image pulls |
| release | 1-2 min | Artifact collection + release creation |
| **Total** | **~15-20 min** | Limited by AMI build parallelism |

---

## Next Steps

- [AMI Builder](ami-builder.md) — understand what goes into the AMI
- [Custom Golden AMIs](golden-ami-customization.md) — add your own software
- [AMI Pipeline Setup](../AMI_PIPELINE_SETUP.md) — one-time AWS account configuration
