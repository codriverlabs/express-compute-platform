# ecp update-cluster

Update cluster configuration. Currently supports refreshing the JWKS public keys
from the cluster (useful after certificate rotation).

## Usage

```
ecp update-cluster [OPTIONS] <name>
```

## Arguments

| Argument | Description |
|----------|-------------|
| `<name>` | Cluster name (required) |

## Options

| Option | Description |
|--------|-------------|
| `--kubeconfig=<kubeconfig>` | Path to kubeconfig (default: `~/.kube/config`) |
| `--refresh-jwks` | Re-read and push JWKS from cluster |

## Examples

```bash
# Refresh JWKS after certificate rotation
ecp update-cluster my-cluster --refresh-jwks

# Refresh JWKS using a specific kubeconfig
ecp update-cluster my-cluster --refresh-jwks --kubeconfig /tmp/kubeconfig
```
