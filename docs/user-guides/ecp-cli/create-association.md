# ecp create-association

Create a workload identity (pod identity association). Binds a Kubernetes
service account to an IAM role so pods using that service account receive
temporary AWS credentials automatically.

## Usage

```
ecp create-association --cluster-name=<clusterName> --namespace=<namespace>
                       --service-account=<serviceAccount> --role-arn=<roleArn>
```

## Options (all required)

| Option | Description |
|--------|-------------|
| `--cluster-name=<clusterName>` | Cluster name |
| `--namespace=<namespace>` | Kubernetes namespace |
| `--service-account=<serviceAccount>` | Kubernetes service account name |
| `--role-arn=<roleArn>` | IAM role ARN to assume |

## Examples

```bash
ecp create-association \
  --cluster-name my-cluster \
  --namespace default \
  --service-account my-app \
  --role-arn arn:aws:iam::123456789012:role/MyAppRole
```

## Aliases

- `ecp create-pod-identity-association` (identical behavior)
