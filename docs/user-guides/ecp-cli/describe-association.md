# ecp describe-association

Show details of a workload identity (pod identity association).

## Usage

```
ecp describe-association --cluster-name=<clusterName> --association-id=<associationId>
```

## Options (all required)

| Option | Description |
|--------|-------------|
| `--cluster-name=<clusterName>` | Cluster name |
| `--association-id=<associationId>` | Association ID |

## Examples

```bash
ecp describe-association \
  --cluster-name my-cluster \
  --association-id a-1234567890abcdef0
```

## Aliases

- `ecp describe-pod-identity-association` (identical behavior)
