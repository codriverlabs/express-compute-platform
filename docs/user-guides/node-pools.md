# Node Pools

This guide covers Karpenter NodePool and EC2NodeClass configuration for Express Compute worker nodes.

---

## Overview

Karpenter manages worker node provisioning. It watches for unschedulable pods and launches EC2 instances that fit the workload requirements. Express Compute uses Karpenter instead of Cluster Autoscaler because:

- **Faster scaling** — seconds to provision, not minutes
- **Right-sizing** — picks the optimal instance type per workload
- **Spot-first** — 60-90% cost savings on worker nodes
- **Consolidation** — removes underutilized nodes automatically

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Control Plane EC2 (golden AMI)                  │
│                                                  │
│  ┌────────────────┐   ┌──────────────────┐      │
│  │ Karpenter      │   │ ecp-karpenter-   │      │
│  │ Controller     │   │ support          │      │
│  │                │   │ (webhook +       │      │
│  │ Watches pods → │   │  validation)     │      │
│  │ Provisions EC2 │   └──────────────────┘      │
│  └───────┬────────┘                              │
│          │                                       │
└──────────┼───────────────────────────────────────┘
           │ LaunchInstances
           ▼
┌──────────────────────────────────────────────────┐
│  Worker Nodes (Spot or On-Demand)                 │
│                                                   │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐    │
│  │ c6g.xlarge│  │ m6g.large │  │ r6g.medium│    │
│  │ (Spot)    │  │ (Spot)    │  │ (OD)      │    │
│  └───────────┘  └───────────┘  └───────────┘    │
└──────────────────────────────────────────────────┘
```

---

## Configuration Files

```
node-pools/
├── spot-nodepool.yaml         # Spot-first NodePool (default workers)
├── ondemand-nodepool.yaml     # On-Demand NodePool (for stateful workloads)
├── test-workload.yaml         # Sample pod for testing Spot provisioning
├── ebs-test-workload.yaml     # Sample pod with persistent volume
├── configure-nodepools.sh     # Runtime configuration script
└── chart/                     # Helm chart for deploying node pools
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
```

---

## Deploying Node Pools

### Using the Configuration Script

After a cluster is running, deploy node pools with:

```bash
/opt/cluster-setup/karpenter/configure-nodepools.sh [variant]
```

Supported variants:
- `al2023` (default) — Amazon Linux 2023
- `al2023-gpu` — AL2023 with NVIDIA GPU support
- `al2023-neuron` — AL2023 with AWS Inferentia/Trainium
- `bottlerocket` — Bottlerocket OS
- `bottlerocket-gpu` — Bottlerocket with NVIDIA
- `bottlerocket-neuron` — Bottlerocket with Inferentia

The script automatically:
1. Detects the Kubernetes version from the running cluster
2. Resolves the correct EKS-optimized AMI via SSM parameters
3. Discovers the VPC subnet and security group
4. Generates and applies EC2NodeClass + NodePool manifests

### Using the Helm Chart

For GitOps-style management:

```bash
helm upgrade --install node-pools /opt/cluster-setup/karpenter/chart \
  --namespace karpenter \
  --set amiId=ami-0abc123 \
  --set subnetId=subnet-xxx \
  --set securityGroupId=sg-xxx \
  --set workerRole=my-tenant-eks-d-worker-node-role
```

---

## NodePool Configuration

### Spot NodePool (Default)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["5"]
  limits:
    cpu: 100
    memory: 100Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
```

Key settings:
- **Spot-only** — maximum cost savings
- **ARM64** — Graviton instances for best price/performance
- **Instance families c/m/r, gen 6+** — broad selection for Spot availability
- **Aggressive consolidation** — nodes removed 1 minute after becoming idle

### On-Demand NodePool (Stateful)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: ondemand
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m"]
  limits:
    cpu: 32
    memory: 64Gi
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 5m
```

Use for workloads that can't tolerate Spot interruptions (databases, stateful services).

---

## EC2NodeClass Configuration

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: <tenant-id>-eks-d-worker-node-role
  amiSelectorTerms:
    - id: <ami-id>    # EKS-optimized AMI resolved at runtime
  subnetSelectorTerms:
    - id: <private-subnet-id>
  securityGroupSelectorTerms:
    - id: <worker-sg-id>
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeType: gp3
        volumeSize: 20Gi
        deleteOnTermination: true
  userData: |
    #!/bin/bash
    /etc/eks/bootstrap.sh <cluster-name>
```

---

## Testing Node Provisioning

### Deploy a Test Workload (Spot)

```bash
kubectl apply -f /opt/cluster-setup/karpenter/test-workload.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 3
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      containers:
        - name: inflate
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.9
          resources:
            requests:
              cpu: 500m
              memory: 256Mi
```

Watch Karpenter provision a node:

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
kubectl get nodes -w
```

### Test EBS Persistent Volumes

```bash
kubectl apply -f /opt/cluster-setup/karpenter/ebs-test-workload.yaml
```

This creates a `PersistentVolumeClaim` and a pod that mounts it, verifying the EBS CSI driver works on Karpenter-provisioned nodes.

---

## Customizing Node Pools

### Targeting Specific Instance Types

```yaml
requirements:
  - key: node.kubernetes.io/instance-type
    operator: In
    values: ["c6g.xlarge", "c6g.2xlarge", "m6g.xlarge"]
```

### GPU Workloads

```yaml
requirements:
  - key: karpenter.k8s.aws/instance-category
    operator: In
    values: ["g", "p"]
  - key: karpenter.sh/capacity-type
    operator: In
    values: ["on-demand"]  # GPU Spot is unreliable
```

### Multi-Architecture

```yaml
requirements:
  - key: kubernetes.io/arch
    operator: In
    values: ["arm64", "amd64"]
```

Karpenter will choose the cheapest available instance across architectures.

### Cost Limits

```yaml
limits:
  cpu: 200         # Max 200 vCPUs across all nodes in this pool
  memory: 400Gi   # Max 400 GiB RAM
```

---

## Disruption and Consolidation

Karpenter continuously optimizes node usage:

| Policy | Behavior | Use case |
|--------|----------|----------|
| `WhenEmptyOrUnderutilized` | Remove nodes that are empty OR can be consolidated | Spot workloads, dev environments |
| `WhenEmpty` | Only remove nodes with no pods | Stateful workloads |

`consolidateAfter` controls the grace period before action:
- `1m` — aggressive (dev/test)
- `5m` — moderate (production Spot)
- `30m` — conservative (production On-Demand)

---

## Monitoring Karpenter

```bash
# Controller logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Provisioning events
kubectl get events --field-selector reason=ProvisioningSucceeded

# Current nodes and their capacity type
kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type

# NodePool status
kubectl get nodepools -o wide
```

---

## Troubleshooting

### Pods Stuck Pending

```bash
# Check if Karpenter sees the pods
kubectl get events --field-selector involvedObject.kind=Pod

# Check NodePool limits
kubectl get nodepools -o yaml | grep -A5 limits

# Check EC2NodeClass is valid
kubectl get ec2nodeclasses -o yaml
```

### Spot Instance Interruptions

Karpenter handles interruptions automatically. When a Spot instance receives a 2-minute warning:
1. Karpenter cordons the node
2. Pods are rescheduled to other nodes (or a new node is launched)
3. The interrupted node is terminated

### Nodes Not Joining

```bash
# On the worker node (if accessible):
journalctl -u kubelet -f

# From the control plane:
kubectl get events --sort-by='.lastTimestamp' | grep -i node
```

---

## Next Steps

- [Cluster Setup](cluster-setup.md) — how Karpenter is installed during boot
- [Architecture](architecture.md) — system design overview
- [Components](components.md) — Karpenter component details
