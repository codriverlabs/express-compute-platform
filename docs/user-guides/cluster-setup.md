# Cluster Setup

This guide explains the cluster boot sequence — what happens when an EC2 instance starts from a golden AMI and becomes a running Kubernetes cluster.

---

## Boot Sequence Overview

When an Express Compute EC2 instance launches, the `ecp-boot.service` systemd unit runs `setup-eks-d.sh`, which executes numbered scripts in order:

```
Instance boot
  └─ systemd starts ecp-boot.service
       └─ /opt/cluster-setup/setup-eks-d.sh
            ├─ 05-prepare-etcd.sh              Mount etcd EBS volume
            ├─ 06-install-aws-iam-authenticator.sh  IAM authenticator config
            ├─ 07-install-eks-d.sh             kubeadm init (control plane)
            ├─ 08-install-cni.sh               AWS VPC CNI
            ├─ 09-install-cloud-provider.sh    AWS Cloud Controller Manager
            ├─ 10-configure-node.sh            Untaint control plane
            ├─ 11-install-cert-manager.sh      TLS certificate management
            ├─ 11b-install-kubelet-csr-approver.sh  CSR auto-approval
            ├─ 12-install-ecp-workload-identity.sh  Workload Identity (if ECP_ENDPOINT set)
            ├─ 13-install-ebs-csi.sh           Persistent storage
            ├─ 14-install-metrics-server.sh    Resource metrics
            ├─ 15-install-karpenter.sh         Node autoscaling
            ├─ 16-install-cloudwatch.sh        Observability
            ├─ 17-monitor-cloudwatch-rollout.sh  Validate CloudWatch agent
            └─ 18-install-ecp-karpenter-support.sh  EC2NodeClass webhook
```

Total boot time: **under 3 minutes** (all images and charts are pre-pulled in the AMI).

---

## Prerequisites

Before `setup-eks-d.sh` runs, the following must exist:

### cluster.env

The file `/opt/eks-d/cluster.env` must be present. It's written by the TenantEc2Service Lambda before instance launch, or manually for dev mode:

```bash
TENANT_ID=alice
CLUSTER_NAME=alice-ecp-arm64
NODE_IP=10.0.1.42
AWS_REGION=us-east-1
ECP_ENDPOINT=https://api.express-compute.example.com   # optional — enables Workload Identity
```

| Variable | Required | Description |
|----------|----------|-------------|
| `TENANT_ID` | Yes | Owner identifier (used for IAM role names, tagging) |
| `CLUSTER_NAME` | Yes | Kubernetes cluster name |
| `NODE_IP` | Yes | Private IP of this instance (used for apiserver advertise address) |
| `AWS_REGION` | Yes | AWS region |
| `ECP_ENDPOINT` | No | Express Compute API endpoint. If unset, step 12 is skipped (dev mode) |

### AMI-baked software

The golden AMI provides everything the boot scripts need:
- All Kubernetes binaries (`kubeadm`, `kubelet`, `kubectl`)
- containerd (running)
- All container images pre-pulled into containerd's image store
- Helm charts staged in `/opt/cluster-setup/charts/`
- The boot scripts themselves in `/opt/cluster-setup/`

---

## Step-by-Step Breakdown

### Step 1: Prepare etcd (05-prepare-etcd.sh)

Mounts the EBS volume designated for etcd data at `/var/lib/etcd`. Creates the filesystem if the volume is blank.

**Why separate volume?** etcd's write performance directly affects Kubernetes API latency. A dedicated gp3 volume with provisioned IOPS avoids contention with the root filesystem.

### Step 2: IAM Authenticator (06-install-aws-iam-authenticator.sh)

Configures `aws-iam-authenticator` so the Kubernetes API server can authenticate users via IAM. Generates the authenticator config and sets up the static pod manifest entry referenced by the apiserver.

**Must run before kubeadm init** — the apiserver config references the authenticator webhook.

### Step 3: EKS-D Init (07-install-eks-d.sh)

Runs `kubeadm init` with:
- The EKS-D image repository (images already present locally)
- The node IP as advertise address
- Pod CIDR suitable for VPC CNI
- The IAM authenticator webhook configuration

After `kubeadm init`, copies the admin kubeconfig to `ec2-user` so the login user has cluster access immediately, even if later steps fail.

### Step 4: VPC CNI (08-install-cni.sh)

Deploys the AWS VPC CNI plugin via Helm. This assigns real VPC IP addresses to pods, enabling direct pod-to-pod communication across the VPC without overlay networks.

### Step 5: Cloud Controller Manager (09-install-cloud-provider.sh)

Installs the AWS Cloud Controller Manager, which manages:
- Node lifecycle (detects instance termination)
- Load balancer provisioning (for Services of type LoadBalancer)
- Node metadata (instance type, availability zone labels)

### Step 6: Configure Node (10-configure-node.sh)

Removes the `node-role.kubernetes.io/control-plane` taint so workloads can be scheduled on the control plane node (single-node dev clusters).

### Step 6b: cert-manager (11-install-cert-manager.sh)

Deploys cert-manager for automatic TLS certificate provisioning. Required by:
- Karpenter webhooks
- Express Compute Workload Identity webhooks
- ecp-karpenter-support webhooks

### Step 6b2: Kubelet CSR Approver (11b-install-kubelet-csr-approver.sh)

Deploys an auto-approver for kubelet serving certificate requests. Replicates the behavior of EKS's built-in CSR approval for worker nodes joining the cluster.

### Step 6c: Workload Identity (12-install-ecp-workload-identity.sh)

**Only runs if `ECP_ENDPOINT` is set.** Registers the cluster with the Express Compute control plane and installs the credential-service webhook that injects pod-level IAM credentials.

In dev/manual mode (no `ECP_ENDPOINT`), this step is skipped gracefully.

### Step 7: EBS CSI Driver (13-install-ebs-csi.sh)

Installs the AWS EBS CSI driver for persistent volume support. Enables `PersistentVolumeClaim` resources backed by EBS gp3 volumes.

### Step 8: Metrics Server (14-install-metrics-server.sh)

Deploys the Kubernetes Metrics Server, which provides:
- `kubectl top nodes` / `kubectl top pods`
- HPA (Horizontal Pod Autoscaler) data source
- Karpenter right-sizing signals

### Step 9: Karpenter (15-install-karpenter.sh)

Installs Karpenter with the tenant-specific configuration:
- Service account with IAM role for EC2 provisioning
- Interrupt handling for Spot instances
- Configured for the cluster's VPC and subnets

### Step 10: CloudWatch (16-install-cloudwatch.sh + 17-monitor-cloudwatch-rollout.sh)

Deploys the CloudWatch agent for:
- Container log collection
- Node and pod metrics
- Cluster-level observability

Step 17 validates the agent reaches a running state before proceeding.

### Step 18: ECP Karpenter Support (18-install-ecp-karpenter-support.sh)

Installs the Express Compute Karpenter support controller:
- EC2NodeClass validating webhook
- `ValidationSucceeded` status controller
- Requires cert-manager (step 11) and Karpenter CRDs (step 15)

---

## Progress Tracking

The boot sequence reports progress via SSM parameters (if the platform is deployed) and stdout. The progress library (`cluster-setup/progress.sh`) provides:

```bash
update_progress "phase" "message" percentage
```

This allows the Express Compute control plane to poll boot status and report readiness to users.

---

## Dev / Manual Mode

You can boot a cluster manually without the Express Compute control plane:

```bash
# SSH into an EC2 instance running the golden AMI
sudo mkdir -p /opt/eks-d
sudo tee /opt/eks-d/cluster.env <<EOF
TENANT_ID=dev
CLUSTER_NAME=dev-cluster
NODE_IP=$(hostname -I | awk '{print $1}')
AWS_REGION=us-east-1
EOF

sudo bash /opt/cluster-setup/setup-eks-d.sh
```

With `ECP_ENDPOINT` omitted, step 12 (Workload Identity) is skipped, and the cluster operates standalone.

---

## Resetting a Cluster

To tear down and rebuild from scratch:

```bash
sudo bash /opt/cluster-setup/reset-cluster.sh
```

This runs `kubeadm reset`, cleans up CNI state, and prepares for a fresh `setup-eks-d.sh` run.

---

## Monitoring Boot Progress

### From the instance (SSH)

```bash
# Follow the boot log in real time
journalctl -u ecp-boot -f

# Check current status
systemctl status ecp-boot
```

### After boot completes

```bash
kubectl get nodes
kubectl get pods -A
```

---

## Troubleshooting

### Boot stalls at kubeadm init

**Symptom:** Step 3 hangs for >2 minutes.

**Common causes:**
- containerd not running: `systemctl status containerd`
- Images not pre-pulled: `sudo ctr -n k8s.io images list | wc -l` (should be 30+)
- Network issue: instance can't reach instance metadata or kubelet can't bind

**Fix:**
```bash
# Check containerd
sudo systemctl restart containerd
# Verify images
sudo ctr -n k8s.io images list | grep kube-apiserver
```

### VPC CNI pods stuck in Init

**Symptom:** `aws-node` pods are `Init:0/1` or `CrashLoopBackOff`.

**Causes:**
- Instance doesn't have the right IAM permissions for ENI management
- The VPC doesn't have enough secondary IPs available

**Fix:** Check the aws-node logs:
```bash
kubectl logs -n kube-system -l k8s-app=aws-node --tail=50
```

### Karpenter can't provision workers

**Symptom:** Pods stay `Pending`, no new nodes appear.

**Causes:**
- No NodePool/EC2NodeClass deployed
- IAM role for Karpenter lacks EC2 permissions
- Subnet or security group selectors don't match

**Fix:**
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
kubectl get nodepools
kubectl get ec2nodeclasses
```

### CloudWatch agent fails

**Symptom:** Step 17 times out waiting for the agent.

**Cause:** Usually an IAM permissions issue or wrong cluster name in the config.

**Fix:**
```bash
kubectl logs -n amazon-cloudwatch -l app.kubernetes.io/name=cloudwatch-agent
```

---

## Next Steps

- [Node Pools](node-pools.md) — configure Karpenter worker nodes
- [Architecture](architecture.md) — understand the system design
- [Components](components.md) — detailed component reference
