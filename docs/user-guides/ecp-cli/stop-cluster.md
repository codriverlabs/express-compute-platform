# ecp stop-cluster

Stop a managed cluster. The EC2 instance is stopped but the EBS volume is preserved,
allowing the cluster to be resumed later without data loss.

## Usage

```
ecp stop-cluster <clusterName>
```

## Arguments

| Argument | Description |
|----------|-------------|
| `<clusterName>` | Cluster name (required) |

## Examples

```bash
ecp stop-cluster my-cluster
```

## Notes

- Only managed clusters can be stopped (self-managed clusters are not controlled by ECP).
- The EBS root volume is preserved — all etcd data, container images, and configuration survive.
- Spot instances cannot be stopped; use on-demand pricing if stop/resume is needed.
- Billing for EC2 compute stops; EBS storage charges continue.
