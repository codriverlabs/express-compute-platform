# k3s-Xpress User Guide

k3s-Xpress delivers production-ready k3s clusters on AWS with a golden AMI
strategy: sub-4-minute boot (~220s typical), zero runtime downloads, full
Workload Identity support, and the same `ecp` CLI lifecycle as EKS-D-Xpress.

---

## Overview

k3s-Xpress is the lightweight alternative to EKS-D-Xpress. It uses k3s
(a CNCF-certified Kubernetes distribution) instead of EKS-D, trading the
full EKS compatibility for dramatically reduced complexity and cost.

**Best for:** dev/staging environments, edge deployments, single-node clusters,
CI runners, and cost-sensitive production workloads.

k3s-Xpress ships with the same VPC-native pod networking (ENI per pod via AWS
VPC CNI) and Karpenter autoscaling as EKS-D-Xpress — these are not
differentiators between the two distributions.

**Use EKS-D-Xpress instead when:** you need full EKS API compatibility, or a
multi-AZ HA control plane. k3s-Xpress currently ships as a single-node server
(SQLite datastore) — k3s itself supports HA via embedded etcd or an external
datastore, but that mode isn't wired into the current `setup-k3s-xpress.sh`
boot script.

---

## Quick Start

### Create a k3s cluster

```bash
ecp create-cluster my-k3s \
  --distribution k3s \
  --arch arm64 \
  --pricing spot \
  --wait
```

### Access the cluster

```bash
ecp get-cluster-access my-k3s
kubectl get nodes
kubectl get pods -A
```

### Delete the cluster

```bash
ecp delete-cluster my-k3s
```

---

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                    k3s-Xpress Instance                          │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  /usr/local/bin/k3s          ← Single binary (server + agent)  │
│  /var/lib/rancher/k3s/       ← Data directory                  │
│  ├── agent/images/           ← Airgap tarballs (pre-loaded)    │
│  ├── server/db/              ← SQLite datastore                │
│  └── server/manifests/       ← Auto-deploy manifests           │
│                                                                │
│  /opt/k3s-xpress/            ← Express Compute additions       │
│  ├── charts/                 ← Pre-cached Helm charts          │
│  ├── cluster-setup/          ← Boot orchestration scripts      │
│  ├── version.env             ← Version pins                    │
│  └── cluster.env             ← Instance-specific config        │
│                                                                │
│  Add-ons (installed at boot):                                  │
│  ├── cert-manager            ← TLS certificate lifecycle       │
│  ├── CloudWatch agent        ← Logs + metrics                  │
│  ├── ECP Workload Identity   ← Pod-level IAM credentials       │
│  └── metrics-server          ← k3s built-in                    │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Boot Sequence (~220s / sub-4-minute target)

1. **Instance starts** — golden AMI with everything pre-installed
2. **k3s-xpress-boot.service** triggers `setup-k3s-xpress.sh`
3. **Resolve metadata** — Node IP, instance ID, region from IMDSv2
4. **Write config** — `/etc/rancher/k3s/config.yaml` with instance-specific values
5. **Start k3s** — single binary boots API server, etcd, scheduler, kubelet
6. **Wait for readiness** — CoreDNS, system pods
7. **Install add-ons** — cert-manager, CloudWatch, verify metrics-server
8. **Register with ECP** — Workload Identity integration
9. **Done** — cluster ready for workloads

---

## Networking

### AWS VPC CNI

k3s-Xpress uses the same AWS VPC CNI as EKS-D-Xpress. The CNI binaries,
container images, and patched manifest are pre-baked into the golden AMI —
there is no runtime download or install step. At boot, `setup-k3s-xpress.sh`
simply `kubectl apply`s the pre-staged manifest. Pods get IPs directly
from the VPC subnet (prefix delegation), enabling VPC-native networking:

- Pod-to-pod traffic is direct (no overlay, no encapsulation)
- SecurityGroups for Pods supported
- VPC flow logs have full visibility into pod traffic
- ENI limits apply (~110 pods per node with prefix delegation on c6g.large)

```
Service CIDR: 10.43.0.0/16
Cluster DNS:  10.43.0.10
Pod IPs:      From VPC subnet (prefix delegation)
```

k3s's built-in Flannel is disabled (`flannel-backend: "none"`) — the VPC CNI
DaemonSet handles all pod networking.

### Load Balancing

Use AWS Load Balancer Controller for Ingress (ALB) and Service type
LoadBalancer (NLB), or NodePort for simple dev access.

---

## Storage

### Default: EBS CSI Driver (pre-installed)

The EBS CSI Driver is installed automatically at boot — the Helm chart and
all images are pre-baked into the golden AMI, so there's nothing to download
or install manually. It ships with a `gp3` StorageClass marked as the
cluster default, giving persistent volumes that survive node replacement:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  storageClassName: gp3
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
```

### Alternative: local-path-provisioner

k3s also includes the built-in `local-path-provisioner`, which creates
PersistentVolumes backed by local node storage. Useful for ephemeral,
single-node, or dev/staging workloads where EBS durability isn't needed —
note that volumes are lost if the node is replaced.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  storageClassName: local-path
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
```

---

## Workload Identity

k3s-Xpress supports the same ECP Workload Identity as EKS-D-Xpress. Pods
receive short-lived AWS credentials scoped to their ServiceAccount.

```bash
# Create an association (same as EKS-D)
ecp create-association my-k3s \
  --service-account my-ns/my-sa \
  --role-arn arn:aws:iam::123456789012:role/my-role
```

---

## Monitoring

CloudWatch agent is installed at boot, providing:
- Container logs → CloudWatch Logs
- Kubernetes metrics → CloudWatch Metrics
- Application Signals (optional)

Logs are available immediately after boot in the `/aws/k3s-xpress/<cluster-name>` log group.

---

## Building the Golden AMI

### Local build

```bash
cd ami-builder
./build-k3s-amis.sh
```

### CI/CD

Push a tag matching `v*` to trigger the `k3s-xpress-release.yml` workflow (the same tag convention used for EKS-D-Xpress releases).

---

## Configuration Reference

### cluster.env (pre-seeded by ECP control plane)

```bash
TENANT_ID=tenant-abc123
CLUSTER_NAME=my-k3s-cluster
NODE_IP=10.0.16.5
AWS_ACCOUNT_ID=123456789012
AWS_REGION=us-east-1
NODE_ROLE_ARN=arn:aws:iam::123456789012:role/express-compute-tenant-abc12345-instance-role
CLUSTER_ENDPOINT=https://10.0.16.5:6443
POD_SUBNET=10.0.0.0/16
PUBLIC_SUBNET_ID=subnet-0aaa111
PRIVATE_SUBNET_ID=subnet-0bbb222
SECURITY_GROUP_ID=sg-0ccc333
ECP_ENDPOINT=https://api.express-compute.example.com
ECP_API_URL=https://api.express-compute.example.com/clusters/my-k3s-cluster/assets
K8S_VERSION=1.35
PROGRESS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/123456789012/...
```

### version.env (baked into AMI)

```bash
K3S_KUBERNETES_VERSION=1.35
K3S_VERSION=v1.35.7+k3s1
CERT_MANAGER_VERSION=v1.20.2
CLOUDWATCH_AGENT_VERSION=v1.300048.1
ECP_CONTROL_PLANE_VERSION=1.3.1
INSTALL_ECP=true
K3S_DISABLE=traefik,servicelb
```

---

## Cost Profile

| Instance | vCPU | RAM | Monthly (Spot) | Use Case |
|----------|------|-----|----------------|----------|
| c6g.large | 2 | 4 GB | ~$20 | Default — full add-on stack |
| c6g.xlarge | 4 | 8 GB | ~$40 | Heavy workloads on server node |

k3s control plane overhead is ~300 MB, but the full add-on stack (Karpenter, ECP WI,
VPC CNI, CloudWatch, EBS CSI, cert-manager) requires ~2 GB. The `c6g.large` default
provides enough headroom for system components plus light server-node workloads.

---

## Comparison: k3s-Xpress vs EKS-D-Xpress

| Feature | k3s-Xpress | EKS-D-Xpress |
|---------|-----------|-------------|
| Boot time | < 4 min (~220s) | < 4 min |
| Min instance | c6g.large (2 vCPU, 4GB) | c6g.large (2 vCPU, 4GB) |
| CNI | VPC CNI (ENI per pod) | VPC CNI (ENI per pod) |
| Datastore | SQLite (2 GB EBS) | etcd (20 GB EBS) |
| Autoscaling | Karpenter | Karpenter |
| EKS API compat | No | Yes |
| Workload Identity | ✓ | ✓ |
| CloudWatch | ✓ | ✓ |
| EBS CSI | ✓ | ✓ |
| Golden AMI | ✓ | ✓ |

---

## Troubleshooting

### Check k3s status

```bash
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

### Check boot progress

```bash
sudo journalctl -u k3s-xpress-boot.service
```

### Reset cluster

```bash
sudo systemctl stop k3s
sudo rm -rf /var/lib/rancher/k3s/server/db /var/lib/rancher/k3s/agent/containerd
sudo rm -rf /etc/rancher/k3s/config.yaml
sudo rm -f /opt/k3s-xpress/.installation_complete
# Then re-run setup:
sudo bash /opt/k3s-xpress/cluster-setup/setup-k3s-xpress.sh
```

### Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| k3s won't start | Missing cluster.env | Ensure TenantEc2Service seeds /opt/k3s-xpress/cluster.env |
| Pods stuck Pending | Airgap images not loaded | Check /var/lib/rancher/k3s/agent/images/ |
| No internet from pods | NAT Gateway missing | Check VPC route tables |
| ECR pull fails | Credential provider not configured | Verify /var/lib/rancher/k3s/agent/etc/credential-provider-config.yaml |
