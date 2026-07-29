# ecp delete-association

Delete a workload identity (pod identity association).

## Usage

```
ecp delete-association --cluster-name=<clusterName> --association-id=<associationId>
```

## Options (all required)

| Option | Description |
|--------|-------------|
| `--cluster-name=<clusterName>` | Cluster name |
| `--association-id=<associationId>` | Association ID (from create or list output) |

## Examples

```bash
ecp delete-association \
  --cluster-name my-cluster \
  --association-id a-1234567890abcdef0
```

## Aliases

- `ecp delete-pod-identity-association` (identical behavior)
