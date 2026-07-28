# ecp list-associations

List workload identities (pod identity associations) for a cluster.
Optionally filter by namespace and/or service account.

## Usage

```
ecp list-associations --cluster-name=<clusterName> [--namespace=<namespace>]
                      [--service-account=<serviceAccount>]
```

## Options

| Option | Required | Description |
|--------|----------|-------------|
| `--cluster-name=<clusterName>` | Yes | Cluster name |
| `--namespace=<namespace>` | No | Filter by namespace |
| `--service-account=<serviceAccount>` | No | Filter by service account |

## Examples

```bash
# List all associations for a cluster
ecp list-associations --cluster-name my-cluster

# Filter by namespace
ecp list-associations --cluster-name my-cluster --namespace production

# Filter by specific service account
ecp list-associations --cluster-name my-cluster \
  --namespace default \
  --service-account my-app
```

## Aliases

- `ecp list-workload-identities` (identical behavior)
