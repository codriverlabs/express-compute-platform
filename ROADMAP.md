# Roadmap — August 2026

Express Compute Platform development priorities for August 2026.

---

## 🎯 August 2026 Priorities

### 1. EKS Add-Ons for EKS-D-Xpress and Self-Managed Distributions

Bring the EKS Add-On lifecycle model to all supported distributions — managed
and self-managed clusters on EC2, and golden AMI builds.

- **Add-On registry**: curated catalog of validated add-ons (VPC CNI, EBS CSI, CoreDNS, kube-proxy, CloudWatch Agent, cert-manager, metrics-server)
- **Versioned lifecycle**: install, upgrade, rollback per add-on with dependency resolution
- **AMI bake integration**: pre-cache add-on charts + images during golden AMI builds
- **Self-managed support**: `ecp install-addon` / `ecp upgrade-addon` for k3s, microk8s, EKS-D clusters
- **Declarative config**: add-on versions pinned in cluster spec, drift detection on reconciliation

### 2. Faster Startup — Parallel Add-On Installation

Reduce cluster boot time by parallelizing independent add-on installations.

- **Dependency graph**: model add-on dependencies (cert-manager → webhooks, CNI → everything)
- **Parallel execution**: install independent add-ons concurrently (EBS CSI ∥ metrics-server ∥ CloudWatch)
- **Target**: sub-3-minute boot for standard cluster profile
- **Progress streaming**: `ecp create-cluster --wait` shows parallel progress per add-on

### 3. OpenTelemetry for Managed Clusters

Built-in observability for managed clusters using OTEL Collector + ADOT.

- **Pre-installed OTEL Collector** in golden AMI (DaemonSet)
- **Auto-instrumentation**: inject OTEL SDKs for Java, Node.js, Python workloads
- **Destinations**: CloudWatch, X-Ray, Prometheus (configurable)
- **Cluster metrics**: control plane, node, pod, container metrics via OTLP
- **Zero-config default**: works out of the box, opt-out per namespace

### 4. Official Guides for k3s and microk8s

Dedicated, tested quick start guides for each distribution.

- **k3s guide**: single-node and HA (embedded etcd), Workload Identity, add-on installation
- **microk8s guide**: snap-based, addons enable pattern, WI integration
- **Tested in CI**: Robot Framework UAT per distribution
- **Distribution-specific notes**: storage classes, CNI differences, upgrade paths

### 5. Managed k3s and microk8s Support

Extend managed cluster provisioning beyond EKS-D to k3s and microk8s.

- `ecp create-cluster my-k3s --distribution k3s --arch=arm64 --wait`
- `ecp create-cluster my-micro --distribution microk8s --arch=arm64 --wait`
- **Golden AMIs per distribution**: k3s and microk8s variants with pre-baked components
- **Same lifecycle**: create, stop, resume, delete, get-cluster-access
- **Same Workload Identity**: identical pod identity experience across distributions

### 6. OpenShift Support via OLM (Operator Lifecycle Manager)

Package Express Compute Workload Identity as an OLM-managed operator for OpenShift.

- **ClusterServiceVersion (CSV)**: operator metadata, RBAC, install strategy
- **OLM catalog**: publish to OperatorHub or private catalog
- **Components**: auth-proxy + workload-identity-webhook + pod-identity-agent as OLM bundle
- **Subscription model**: automatic upgrades via OLM approval strategy

---

## 🚀 Community Edition Enhancements (feeding PRO / Enterprise)

### Community (Free)

| Feature | Description | Upsell to |
|---------|-------------|-----------|
| **Cluster Blueprints** | Pre-defined cluster profiles (dev, staging, production) with sensible defaults | PRO: custom blueprints with policy enforcement |
| **Cost Visibility** | `ecp cluster-cost` — show EC2/EBS/network spend per cluster | PRO: optimization recommendations, idle detection |
| **Health Checks** | `ecp health-check` — validate cluster state, add-on versions, certificate expiry | PRO: continuous monitoring + auto-remediation |
| **Addon CLI** | `ecp install-addon` / `ecp list-addons` — core add-on management | PRO: enterprise add-on catalog + approval workflows |
| **Backup (manual)** | `ecp backup-cluster` — etcd snapshot to S3 | PRO: scheduled backups + cross-region DR |
| **Cross-cloud Workload Identity** | Validated guides for WI from on-prem, Azure, GCP, Oracle Cloud | PRO: multi-cloud identity federation with central policy |
| **Security scan** | `ecp scan-cluster` — CIS benchmark, outdated images, exposed services | Enterprise: continuous compliance + audit trail |

### PRO

| Feature | Description |
|---------|-------------|
| **Multi-cluster fleet management** | Unified view, bulk operations, fleet-wide upgrades |
| **Cost optimization** | Right-sizing recommendations, Spot interruption handling, idle cluster detection |
| **Advanced monitoring** | Custom dashboards, anomaly detection, SLO tracking |
| **Scheduled operations** | Auto-stop/resume on schedule, maintenance windows |
| **Custom blueprints + policy** | Organization-specific cluster templates with guardrails |
| **Priority support** | 8-hour SLA, dedicated Slack channel |
| **GPU/ML workload profiles** | NVIDIA operator, MIG partitioning, training job scheduling |
| **Multi-cloud identity federation** | Centralized WI policy across AWS, Azure, GCP, OCI clusters |

### Enterprise

| Feature | Description |
|---------|-------------|
| **Multi-tenancy** | Isolated namespaces with resource quotas, network policies, tenant RBAC |
| **Audit + compliance** | Full audit trail, SOC2/HIPAA cluster profiles, automated evidence collection |
| **SSO/SAML integration** | OIDC federation with corporate IdP for `ecp` CLI and dashboard |
| **Air-gapped deployment** | Fully offline installation, private registry support, no internet dependency |
| **Hybrid edge** | Clusters on edge locations with central management plane |
| **Auto-remediation** | Self-healing clusters: restart failed components, replace unhealthy nodes |
| **SLA guarantee** | 99.9% control plane availability, 4-hour support response |
| **Custom distributions** | Bring-your-own Kubernetes build with ECP management layer |

---

## 📅 Timeline

| Week | Focus |
|------|-------|
| Aug 4–8 | EKS Add-On registry + lifecycle CLI, parallel boot prototype |
| Aug 11–15 | OTEL collector integration, k3s/microk8s golden AMI variants |
| Aug 18–22 | OLM operator bundle, official distribution guides + UAT |
| Aug 25–29 | Managed k3s/microk8s launch, community blueprint + cost CLI |

---

## 📐 Design Principles

- **Distribution-agnostic**: Workload Identity and add-on lifecycle work identically across EKS-D, k3s, microk8s, OpenShift
- **Offline-first**: golden AMI strategy extends to all distributions — no runtime downloads in managed mode
- **Community-driven**: core features are open, commercial tiers add fleet/enterprise capabilities
- **Backward-compatible**: existing clusters continue working unchanged during upgrades
