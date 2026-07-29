# ecp get-cluster-access

Show SSH connection details for a managed cluster. Can optionally retrieve
the SSH private key from Secrets Manager.

## Usage

```
ecp get-cluster-access [OPTIONS] <name>
```

## Arguments

| Argument | Description |
|----------|-------------|
| `<name>` | Cluster name (required) |

## Options

| Option | Description |
|--------|-------------|
| `--output=<output>` | Output format: `text` or `json` |
| `--print-key` | Re-fetch the SSH private key from Secrets Manager and print it to stdout |
| `--region=<region>` | AWS region (defaults to configured region) |
| `--save-key` | Re-fetch the SSH private key from Secrets Manager and save/overwrite the local `.pem` file |

## Examples

```bash
# Show connection details
ecp get-cluster-access my-cluster

# Save SSH key to local file for direct SSH
ecp get-cluster-access my-cluster --save-key
ssh -i ~/.ecp/my-cluster.pem ubuntu@<ip>

# Print key to stdout (pipe-friendly)
ecp get-cluster-access my-cluster --print-key > /tmp/key.pem
chmod 600 /tmp/key.pem

# JSON output for scripting
ecp get-cluster-access my-cluster --output json
```

## Notes

- The SSH key is stored in AWS Secrets Manager and retrieved on demand.
- The `--ssh-cidr` used during `create-cluster` restricts which IPs can connect.
- For clusters created without `--eip`, the public IP may change on stop/resume.
