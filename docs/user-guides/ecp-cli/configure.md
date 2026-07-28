# ecp configure

Configure Express Compute control plane endpoint and region.

## Usage

```
ecp configure [--endpoint=<endpoint>] [--region=<region>]
```

## Options

| Option | Description |
|--------|-------------|
| `--endpoint=<endpoint>` | Express Compute API endpoint URL |
| `--region=<region>` | AWS region |

## Examples

```bash
# Set endpoint and region
ecp configure --endpoint https://ecp.codriverlabs.ai --region eu-west-1

# Change region only
ecp configure --region us-east-1
```

## Notes

Configuration is stored locally and used as defaults for subsequent commands.
Most commands also accept `--region` to override per-invocation.
