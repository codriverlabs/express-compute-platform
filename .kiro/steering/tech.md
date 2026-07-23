# Technical Steering

## Release Tagging

- Never recreate or move an existing tag. Always bump to the next RC number (e.g. `v1.0.0-rc1` → `v1.0.0-rc2`).
- Ensure all required files are committed and pushed to `main` before creating a release tag.
- Tags trigger the `release.yml` workflow (AMI builds). The `bundle-release.yml` workflow is manual (`workflow_dispatch`).

## GitHub OIDC (AWS)

- GitHub uses immutable OIDC subject claims with org/repo IDs appended: `repo:codriverlabs@236268168/express-compute-platform@1250509430:ref:...`
- The CDK stack requires `githubOrgId` and `githubRepoId` context parameters to generate the correct trust policy.
- The trust policy only allows `refs/heads/main` and `refs/tags/v*`.

## GitHub Repository Rules

- Tag creation is restricted by the `v_release_tagging` ruleset. Repo admins can bypass.

## Action Versions

- Use `aws-actions/configure-aws-credentials@v6` (Node 24 compatible).
- Use `actions/checkout@v6`.
