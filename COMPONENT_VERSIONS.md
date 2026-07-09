# EKS-D Component Versions

Pinned versions from the official EKS-D release manifests. Not all components are rebuilt for each Kubernetes version — only when changes are required.

## Version Matrix

| Component | 1.35 (`eks-1-35-9`) | 1.36 (`eks-1-36-2`) |
|-----------|---------------------|---------------------|
| **Core Kubernetes** | | |
| kube-apiserver | v1.35.4 | v1.36.0 |
| kube-controller-manager | v1.35.4 | v1.36.0 |
| kube-scheduler | v1.35.4 | v1.36.0 |
| kubelet | v1.35.4 | v1.36.0 |
| pause | v1.35.4 | v1.36.0 |
| kube-proxy | v1.35.4 | v1.36.0 |
| etcd | v3.5.21 | v3.5.21 |
| **Authentication** | | |
| aws-iam-authenticator | v0.7.13 | v0.7.15 |
| **Add-ons** | | |
| coredns | v1.14.2 | v1.14.2 |
| metrics-server | v0.7.2 | v0.7.2 |
| **CSI Sidecars** | | |
| external-attacher | v4.9.0 | v4.9.0 |
| external-provisioner | v5.3.0 | v5.3.0 |
| external-resizer | v1.14.0 | v1.14.0 |
| external-snapshotter | v8.3.0 | v8.3.0 |
| node-driver-registrar | v2.14.0 | v2.14.0 |
| livenessprobe | v2.16.0 | v2.16.0 |
| **Networking** | | |
| cni-plugins | v1.7.1 | v1.7.1 |
| aws-vpc-cni | v1.22.3 | — (managed add-on) |
| aws-ebs-csi-driver | v1.38.0 | — (managed add-on) |

> `aws-vpc-cni` and `aws-ebs-csi-driver` are EKS managed add-ons and are not part of the EKS-D release manifest.

## Verification

```bash
curl -s https://distro.eks.amazonaws.com/kubernetes-1-35/kubernetes-1-35-eks-9.yaml
curl -s https://distro.eks.amazonaws.com/kubernetes-1-36/kubernetes-1-36-eks-2.yaml
```

## References

- [EKS-D Release Manifests](https://distro.eks.amazonaws.com/)
- [EKS-D GitHub Releases](https://github.com/aws/eks-distro/releases)
