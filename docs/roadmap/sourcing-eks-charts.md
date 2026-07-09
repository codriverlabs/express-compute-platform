# Sourcing EKS Charts Directly

## Overview

AWS publishes an official Helm repository at **https://aws.github.io/eks-charts** (source:
[aws/eks-charts](https://github.com/aws/eks-charts)). Several components we currently install
via raw manifest `kubectl apply` could instead be managed as versioned Helm releases sourced
directly from this repo. This gives us pinned chart versions, structured `values.yaml` overrides,
and a single upgrade path across components.

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

---

## Charts Available in `eks/` Relevant to EKS-D-Xpress

| Chart | Current install method | Chart name | Notes |
|---|---|---|---|
| **AWS VPC CNI** | raw manifest (`aws-k8s-cni.yaml`) | `eks/aws-vpc-cni` | Already sourced from `amazon-vpc-cni-k8s` repo; Helm is the recommended upgrade path |
| **AWS Load Balancer Controller** | not yet installed | `eks/aws-load-balancer-controller` | Optional — useful if we expose services via ALB/NLB |
| **CloudWatch Metrics** | raw DaemonSet | `eks/aws-cloudwatch-metrics` | Replaces hand-rolled CloudWatch agent manifest |
| **AWS for Fluent Bit** | not yet installed | `eks/aws-for-fluent-bit` | Log forwarding to CloudWatch Logs; alternative to current cloudwatch-agent approach |
| **CNI Metrics Helper** | not yet installed | `eks/cni-metrics-helper` | Publishes VPC CNI metrics (IP pool usage, throttling) to CloudWatch |

Charts **not** in `eks/` that we use (sourced from their own repos):

| Chart | Helm repo | Notes |
|---|---|---|
| cert-manager | `https://charts.jetstack.io` | `jetstack/cert-manager` |
| Karpenter | `oci://public.ecr.aws/karpenter` | OCI chart from Public ECR |
| AWS EBS CSI Driver | `https://kubernetes-sigs.github.io/aws-ebs-csi-driver` | `aws-ebs-csi-driver/aws-ebs-csi-driver` |

---

## AWS VPC CNI — Helm vs Raw Manifest (Current)

We currently download the raw manifest and patch it in-place via a Python script
(`ami-builder/scripts/components/vpc-cni.sh`). The Helm chart approach allows the same
configuration to be expressed declaratively in `values.yaml` and is the upstream-recommended
method.

### Current approach (raw manifest)

```bash
curl -fsSL https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v1.22.3/config/master/aws-k8s-cni.yaml \
  -o /opt/eks-d/manifests/aws-vpc-cni.yaml
# then: python patch for ENABLE_PREFIX_DELEGATION, WARM_PREFIX_TARGET, WARM_ENI_TARGET
kubectl apply -f /opt/eks-d/manifests/aws-vpc-cni.yaml
```

### Helm equivalent

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-vpc-cni eks/aws-vpc-cni \
  --namespace kube-system \
  --version 1.22.3 \
  --set env.ENABLE_PREFIX_DELEGATION=true \
  --set env.WARM_PREFIX_TARGET=1 \
  --set env.WARM_ENI_TARGET=0
```

Key chart parameters relevant to our configuration:

| Parameter | Value we set | Description |
|---|---|---|
| `env.ENABLE_PREFIX_DELEGATION` | `"true"` | Enables /28 prefix delegation for high pod density |
| `env.WARM_PREFIX_TARGET` | `"1"` | Keep 1 spare prefix warm |
| `env.WARM_ENI_TARGET` | `"0"` | Disable spare ENI target (prefix delegation makes it redundant) |
| `image.region` | `us-west-2` | Region for ECR account `602401143452` (VPC CNI always pulls from us-west-2) |

### Adopting the existing aws-node DaemonSet under Helm management

If the DaemonSet is already deployed (e.g. via `kubectl apply`), Helm can adopt it without
re-creating the resources:

```bash
for kind in daemonSet clusterRole clusterRoleBinding serviceAccount; do
  kubectl -n kube-system annotate --overwrite $kind aws-node \
    meta.helm.sh/release-name=aws-vpc-cni \
    meta.helm.sh/release-namespace=kube-system
  kubectl -n kube-system label --overwrite $kind aws-node \
    app.kubernetes.io/managed-by=Helm
done
kubectl -n kube-system annotate --overwrite configmap amazon-vpc-cni \
  meta.helm.sh/release-name=aws-vpc-cni \
  meta.helm.sh/release-namespace=kube-system
kubectl -n kube-system label --overwrite configmap amazon-vpc-cni \
  app.kubernetes.io/managed-by=Helm

helm upgrade --install aws-vpc-cni eks/aws-vpc-cni \
  --namespace kube-system \
  --set originalMatchLabels=true \
  --set env.ENABLE_PREFIX_DELEGATION=true \
  --set env.WARM_PREFIX_TARGET=1 \
  --set env.WARM_ENI_TARGET=0
```

---

## Migration Considerations

### AMI build phase (vpc-cni.sh)

The AMI bake pre-pulls images and pre-bakes CNI binaries. Even if we switch runtime installation
to Helm, the AMI script still needs the manifest to enumerate images for `ctr pull`. Two options:

1. **Keep raw manifest for AMI bake, use Helm at install time** — simplest; the manifest and Helm
   chart are both sourced from the same tag, so image lists are identical.
2. **Use `helm template` to render the manifest for image extraction** — avoids maintaining a
   separate curl download, but adds a Helm dependency to the AMI build environment.

Option 1 is recommended for now. The `vpc-cni.sh` script already uses `--fail` on the curl
download; switching the runtime install step (in `eks-d-setup/08-install-cni.sh`) to Helm is
the higher-value change.

### Versioning

Chart versions in `eks/aws-vpc-cni` track the CNI release versions (e.g. chart `1.22.3` installs
VPC CNI `v1.22.3`). When bumping the CNI version, update both:

- `ami-builder/scripts/components/vpc-cni.sh` — manifest URL and image pull version
- `eks-d-setup/08-install-cni.sh` — runtime Helm chart version (once migrated)
- `COMPONENT_VERSIONS.md` — version matrix table

---

## Roadmap Items

- [ ] **Migrate `08-install-cni.sh` to `helm upgrade --install eks/aws-vpc-cni`** — replaces
  `kubectl apply -f` + manual env patching with a declarative values file.
- [ ] **Migrate CloudWatch agent to `eks/aws-cloudwatch-metrics` or `eks/aws-for-fluent-bit`** —
  evaluate which fits the current CloudWatch integration better.
- [ ] **Add `eks/cni-metrics-helper`** — surfaces IP pool exhaustion and ENI throttling metrics
  to CloudWatch; useful for diagnosing slow pod scheduling.
- [ ] **Centralise Helm repo bootstrap** — add a single `helm-repos.sh` (or step in
  `setup-eks-d.sh`) that registers all needed repos (`eks`, `jetstack`, `aws-ebs-csi-driver`)
  before any install script runs, removing the ad-hoc `helm repo add` calls scattered across
  numbered scripts.

---

## References

- [aws/eks-charts](https://github.com/aws/eks-charts) — chart sources
- [aws.github.io/eks-charts](https://aws.github.io/eks-charts) — Helm index
- [aws-vpc-cni chart README (v1.22.3)](https://github.com/aws/amazon-vpc-cni-k8s/blob/v1.22.3/charts/aws-vpc-cni/README.md)
- [amazon-vpc-cni-k8s releases](https://github.com/aws/amazon-vpc-cni-k8s/releases)
