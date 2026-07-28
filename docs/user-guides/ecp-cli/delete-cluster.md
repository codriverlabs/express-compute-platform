# ecp delete-cluster

Delete a cluster. For managed clusters this is a full teardown (EC2, EBS, SG, etc.).
For self-managed clusters this deregisters them from the control plane.

## Usage

```
ecp delete-cluster [OPTIONS] <name>
```

## Arguments

| Argument | Description |
|----------|-------------|
| `<name>` | Cluster name (required) |

## Options

| Option | Description |
|--------|-------------|
| `--output=<output>` | Output format: `text` or `json` |
| `--region=<region>` | AWS region |

## Examples

```bash
ecp delete-cluster my-cluster

ecp delete-cluster my-cluster --region eu-west-1 --output json
```
