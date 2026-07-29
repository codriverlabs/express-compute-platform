# ecp CLI Reference

The `ecp` command-line interface manages Express Compute clusters and workload identities.

> **Use `ecp` directly** — it is on PATH inside the bundle container. Do not use `./deploy.sh ecp`.

```
Usage: ecp [-hV] [COMMAND]
Express Compute Control Plane Service with Workload Identity for EKS-DX, EKS-D,
k3s, and microk8s clusters
  -h, --help      Show this help message and exit.
  -V, --version   Print version information and exit.
```

## Commands

| Command | Description |
|---------|-------------|
| [configure](configure.md) | Configure control plane endpoint and region |
| [create-cluster](create-cluster.md) | Create a managed cluster or register a self-managed one |
| [delete-cluster](delete-cluster.md) | Delete a cluster (managed: full teardown; self-managed: deregister) |
| [stop-cluster](stop-cluster.md) | Stop a managed cluster (EC2 stopped, EBS preserved) |
| [resume-cluster](resume-cluster.md) | Resume a stopped managed cluster |
| [describe-cluster](describe-cluster.md) | Show details of a registered cluster |
| [list-clusters](list-clusters.md) | List all registered clusters |
| [update-cluster](update-cluster.md) | Update cluster configuration (e.g. refresh JWKS) |
| [create-association](create-association.md) | Create a workload identity (pod identity association) |
| [delete-association](delete-association.md) | Delete a workload identity |
| [describe-association](describe-association.md) | Show details of a workload identity |
| [list-associations](list-associations.md) | List workload identities for a cluster |
| [get-cluster-access](get-cluster-access.md) | Show SSH connection details for a managed cluster |

## Quick Examples

```bash
# Configure endpoint (one-time)
ecp configure --endpoint https://ecp.codriverlabs.ai --region eu-west-1

# Create a cluster (blocks until ready, SSH locked to your IP)
ecp create-cluster my-cluster \
  --arch=arm64 \
  --pricing=spot \
  --ssh-cidr "$(curl -s https://checkip.amazonaws.com/)/32" \
  --wait

# List clusters
ecp list-clusters

# Get SSH access
ecp get-cluster-access my-cluster --save-key

# Stop (preserves EBS)
ecp stop-cluster my-cluster

# Resume
ecp resume-cluster my-cluster --wait

# Add workload identity
ecp create-association \
  --cluster-name my-cluster \
  --namespace default \
  --service-account my-app \
  --role-arn arn:aws:iam::123456789012:role/MyAppRole

# Delete cluster
ecp delete-cluster my-cluster
```
