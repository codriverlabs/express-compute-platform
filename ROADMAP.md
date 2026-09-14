# Roadmap — November 2026

Express Compute Platform development priorities for November 2026.

---

## ✅ Shipped (September 2026)

### k3s-Xpress GA

Production-ready k3s distribution with full feature parity to EKS-D-Xpress:

- `ecp create-cluster --distribution k3s` — sub-4-minute boot, golden AMI
- VPC CNI (always-on), Karpenter with EKS Optimized AMI workers
- aws-iam-authenticator, ECP Workload Identity, CloudWatch, EBS CSI
- AWS Cloud Controller Manager with correct providerID (`aws:///`)
- Dedicated data volume for SQLite state (consistent with EKS-D etcd)
- kubelet-csr-approver for worker node serving certs
- Acceptance-tested end-to-end: cluster → add-ons → Karpenter worker → EBS PVCs

---

## 🎯 November 2026 Priorities

### 1. EKS Add-Ons for EKS-D-Xpress and k3s-Xpress

Bring the EKS Add-On lifecycle model to all supported distributions — managed
and self-managed clusters on EC2, and golden AMI builds.

- **Add-On registry**: curated catalog of validated add-ons (VPC CNI, EBS CSI, CoreDNS, kube-proxy, CloudWatch Agent, cert-manager, metrics-server)
- **Versioned lifecycle**: install, upgrade, rollback per add-on with dependency resolution
- **AMI bake integration**: pre-cache add-on charts + images during golden AMI builds
- **Self-managed support**: `ecp install-addon` / `ecp upgrade-addon` for k3s, microk8s, EKS-D clusters
- **Declarative config**: add-on versions pinned in cluster spec, drift detection on reconciliation

### 2. Per-Component Workload Identity (Least-Privilege)

Move from broad instance role to per-component IAM via ECP Workload Identity.

- **Indexed from EKS Add-Ons**: IAM policies per component extracted from `eks describe-addon-configuration`
- **Stored in repo**: `docs/reference/addon-iam-policies/` — updated by periodic CI job
- **Per-component associations**: VPC CNI, EBS CSI, Karpenter, CloudWatch each get scoped IAM roles
- **Instance role stripped**: SSM + ECR only — everything else via pod-level credentials
- **Same model for both distributions**: EKS-D and k3s use identical association pattern

### 3. Worker Node Image Caching

Eliminate internet dependency for Karpenter workers.

- **ECR pull-through cache** (short-term): workers pull from private ECR via VPC endpoint, first pull cached
- **Spegel peer-to-peer** (medium-term): control plane serves images to workers over VPC network
- **Dual-arch airgap** (long-term): single tarball with arm64 + x86_64 for fully airgapped workers

### 4. Faster Startup — Parallel Add-On Installation

Reduce cluster boot time by parallelizing independent add-on installations.

- **Dependency graph**: model add-on dependencies (cert-manager → webhooks, CNI → everything)
- **Parallel execution**: install independent add-ons concurrently (EBS CSI ∥ metrics-server ∥ CloudWatch)
- **Target**: sub-2-minute boot for k3s, sub-3-minute for EKS-D
- **Progress streaming**: `ecp create-cluster --wait` shows parallel progress per add-on

### 5. OpenTelemetry for Managed Clusters

Built-in observability for managed clusters using OTEL Collector + ADOT.

- **Pre-installed OTEL Collector** in golden AMI (DaemonSet)
- **Auto-instrumentation**: inject OTEL SDKs for Java, Node.js, Python workloads
- **Destinations**: CloudWatch, X-Ray, Prometheus (configurable)
- **Cluster metrics**: control plane, node, pod, container metrics via OTLP
- **Zero-config default**: works out of the box, opt-out per namespace

### 6. k3s HA Mode (3-Node Embedded etcd)

Multi-server k3s clusters for production HA.

- **3-node embedded etcd**: automatic leader election, no external datastore
- **Karpenter-compatible**: workers join any server node
- **Rolling upgrades**: one server at a time with drain + cordon
- **Shared data volume**: EBS for etcd WAL (same DLM snapshot policy)

### 7. OpenShift Support via OLM (Operator Lifecycle Manager)

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
| **Backup (manual)** | `ecp backup-cluster` — etcd/SQLite snapshot to S3 | PRO: scheduled backups + cross-region DR |
| **Hybrid Workload Identity** | Validated guides for accessing AWS services from clusters on Azure VMs, developer laptops, and on-premises infrastructure | PRO: priority support + advanced troubleshooting |
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
| **Advanced backup + DR** | Scheduled etcd snapshots, cross-region restore, RTO/RPO targets |

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
| Nov 3–7 | EKS Add-On registry + lifecycle CLI, per-component WI |
| Nov 10–14 | Worker image caching (ECR pull-through), parallel boot |
| Nov 17–21 | OTEL collector integration, k3s HA mode prototype |
| Nov 24–28 | OLM operator bundle, community blueprint + cost CLI |

---

## 📐 Design Principles

- **Distribution-agnostic**: Workload Identity and add-on lifecycle work identically across EKS-D, k3s, microk8s, OpenShift
- **Offline-first**: golden AMI strategy extends to all distributions — no runtime downloads in managed mode
- **Community-driven**: core features are open, commercial tiers add fleet/enterprise capabilities
- **Backward-compatible**: existing clusters continue working unchanged during upgrades
