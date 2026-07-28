# Express Compute Platform — CLI UAT (Robot Framework)

Automated User Acceptance Tests for the `ecp` CLI — validates that
customer-facing commands work exactly as documented.

> **Important**: These tests invoke `ecp` directly (not `./deploy.sh ecp`).
> Customers should always use `ecp` on PATH — the `deploy.sh ecp` passthrough
> exists only as legacy glue inside the bundle container.

## CLI Command Reference

```
ecp create-cluster          Create a managed cluster or register self-managed
ecp delete-cluster          Delete / deregister a cluster
ecp stop-cluster            Stop a managed cluster (EC2 stopped, EBS preserved)
ecp resume-cluster          Resume a stopped managed cluster
ecp describe-cluster        Show details of a registered cluster
ecp list-clusters           List all registered clusters
ecp update-cluster          Update cluster configuration (e.g. refresh JWKS)
ecp create-association      Create a workload identity (pod identity association)
ecp delete-association      Delete a workload identity
ecp describe-association    Show details of a workload identity
ecp list-associations       List workload identities for a cluster
ecp get-cluster-access      Show SSH connection details for a managed cluster
ecp configure               Configure control plane endpoint and region
```

## Prerequisites

```bash
pip install robotframework
```

The environment must have:
- Valid AWS credentials for the target region
- Control plane deployed (`deploy.sh deploy` completed)
- `ecp` CLI on PATH **OR** internet access (auto-downloaded from GitHub release if missing)
- `curl` for CLI download and SSH CIDR resolution

## Quick Start

```bash
cd uat

# Smoke tests only (no cluster creation, fast)
robot --outputdir results -i smoke tests/

# All tests except lifecycle (no real clusters created)
robot --outputdir results --exclude lifecycle tests/

# Full run including cluster create/delete (~5 min)
robot --outputdir results tests/
```

## Override Variables

```bash
robot --variable REGION:us-east-1 \
      --variable ECP_CLI:/opt/ecp/bin/ecp \
      --outputdir results tests/
```

## Structure

```
uat/
├── resources/
│   ├── variables.robot       # Region, CLI path, timeouts
│   ├── common.resource       # Shared keywords (ECP CLI, wait helpers)
│   └── ecp_setup.resource    # Prerequisite verification
├── tests/
│   ├── __init__.robot        # Directory-level setup (verifies prerequisites)
│   ├── 01_cli_basics.robot       # Version, help, error codes (6 tests)
│   ├── 02_clusters_list.robot    # List/describe basics (3 tests)
│   ├── 03_cluster_lifecycle.robot # create→ready→stop→resume→delete (9 tests)
│   ├── 04_error_handling.robot   # Edge cases and bad input (7 tests)
│   └── 05_workload_identity.robot # Pod identity associations CRUD (5 tests)
└── results/                  # Generated reports (gitignored)
```

## Tags

| Tag | Meaning |
|-----|---------|
| `smoke` | Minimal subset — fast, no infra changes |
| `cli-basics` | Version/help/flags validation |
| `clusters-list` | List/describe command tests |
| `lifecycle` | Full cluster create/stop/resume/delete (slow, ~5 min) |
| `workload-identity` | Pod identity association CRUD |
| `critical` | Must-pass for release |
| `destructive` | Terminates clusters or deletes associations |
| `error-handling` | Bad input / missing resources |

## Design Decisions

### Why `ecp` directly and not `./deploy.sh ecp`?

The Dockerfile adds `/opt/ecp/bin` to `PATH`. Inside the bundle container,
`ecp` is a first-class command. The `./deploy.sh ecp` passthrough is just
a `exec "${SCRIPT_DIR}/bin/ecp" "$@"` — it adds no value and teaches customers
the wrong invocation pattern.

These tests validate the customer experience: `ecp list-clusters`, not
`./deploy.sh ecp list-clusters`.

### Pattern reuse from KubeMicroVM UAT

This suite follows the same Robot Framework conventions established in the
KubeMicroVM UAT:
- Numbered test files for execution order
- `resources/` for shared keywords and variables
- `__init__.robot` for directory-level setup
- Tags for selective execution (smoke, critical, destructive)
- Suite teardown for best-effort cleanup
- Results stored per-version in `results/` for comparison across releases
