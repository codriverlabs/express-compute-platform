# ecp resume-cluster

Resume a stopped managed cluster. The EC2 instance is started and the cluster
returns to a READY state.

## Usage

```
ecp resume-cluster [OPTIONS] <clusterName>
```

## Arguments

| Argument | Description |
|----------|-------------|
| `<clusterName>` | Cluster name (required) |

## Options

| Option | Description |
|--------|-------------|
| `--output=<output>` | Output format: `text` or `json` |
| `--wait` | Wait until cluster is reachable |

## Examples

```bash
# Resume and return immediately
ecp resume-cluster my-cluster

# Resume and wait until ready
ecp resume-cluster my-cluster --wait
```
