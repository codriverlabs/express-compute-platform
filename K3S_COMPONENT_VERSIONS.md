# k3s-Xpress Component Versions

Pinned versions for the k3s-Xpress golden AMI, aligned with the EKS-D version matrix.

## Version Matrix

| Component | 1.35 (`v1.35.7+k3s1`) | 1.36 (`v1.36.3+k3s1`) |
|-----------|----------------------|----------------------|
| **Core** | | |
| k3s | v1.35.7+k3s1 | v1.36.3+k3s1 |
| Kubernetes | v1.35.7 | v1.36.3 |
| etcd (embedded) | v3.6.14-k3s1 | v3.6.14-k3s1 |
| containerd (embedded) | v2.4.x | v2.4.x |
| runc | v1.4.2 | v1.4.2 |
| **Networking** | | |
| flannel | v0.28.4 | v0.28.4 |
| coredns | v1.14.6 | v1.14.6 |
| **Cluster Services** | | |
| metrics-server | v0.9.0 | v0.9.0 |
| local-path-provisioner | v0.0.36 | v0.0.36 |
| helm-controller | v0.17.7 | v0.17.7 |
| kine (SQLite backend) | v0.16.3 | v0.16.3 |
| **Disabled by default** | | |
| traefik | disabled | disabled |
| servicelb | disabled | disabled |

## Add-On Versions (shared)

| Component | Version | Notes |
|-----------|---------|-------|
| cert-manager | v1.20.2 | TLS for webhooks |
| CloudWatch Agent | v1.300048.1 | Observability |
| AWS Cloud Controller Manager | TBD | LoadBalancer + Node lifecycle |
| EBS CSI Driver | v1.38.0 | Optional — persistent volumes |
| ECP Workload Identity | 1.1.6 | auth-proxy + webhook + pod-identity-agent |
| ecp CLI | 1.1.6 | Cluster lifecycle management |
| ECR credential provider | (shared with EKS-D) | Private registry auth |
| Helm | v3.16.x | Chart installation |
| syft | 1.22.0 | SBOM generation |

## k3s Server Configuration

```yaml
# /etc/rancher/k3s/config.yaml
write-kubeconfig-mode: "0644"
disable:
  - traefik
  - servicelb
node-label:
  - "node.kubernetes.io/instance-type=INSTANCE_TYPE"
  - "topology.kubernetes.io/zone=AVAILABILITY_ZONE"
kubelet-arg:
  - "image-credential-provider-bin-dir=/usr/bin"
  - "image-credential-provider-config=/etc/kubernetes/credential-provider/config.yaml"
  - "cloud-provider=external"
```

## Verification

```bash
# Check latest k3s stable releases
curl -s https://update.k3s.io/v1-release/channels | jq '.data[] | select(.id=="v1.35")'
curl -s https://update.k3s.io/v1-release/channels | jq '.data[] | select(.id=="v1.36")'

# Verify installed version
k3s --version

# Verify airgap images loaded
k3s crictl images
```

## References

- [k3s Releases](https://github.com/k3s-io/k3s/releases)
- [k3s v1.35.X Release Notes](https://docs.k3s.io/release-notes/v1.35.X)
- [k3s v1.36.X Release Notes](https://docs.k3s.io/release-notes/v1.36.X)
- [k3s Airgap Install](https://docs.k3s.io/installation/airgap)
- [k3s Configuration](https://docs.k3s.io/installation/configuration)
