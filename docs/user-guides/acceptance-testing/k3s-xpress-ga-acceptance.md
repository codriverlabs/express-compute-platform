# k3s-Xpress GA — Acceptance Test Plan

## Prerequisites

- Fresh k3s-Xpress AMI built with all fixes
- Control plane deployed (`express-compute-control-plane` on `feature/k3s-xpress-ga`)
- Shared infra deployed (`express-compute-managed-k8s-infra` on `feature/k3s-xpress-ga`)
- `ecp` CLI configured

---

## Test 1: Cluster Creation

**Action:**
```bash
ecp create-cluster k3s-acceptance \
  --distribution k3s \
  --arch arm64 \
  --pricing ondemand \
  --k8s-version 1.35 \
  --wait
```

**Expected:**
- [ ] Cluster reaches 100% / `ready` state
- [ ] Boot completes within 300s (systemd timeout)
- [ ] All boot steps pass: data volume → IAM auth → k3s config → CCM → VPC CNI → add-ons → Karpenter

---

## Test 2: Node Verification

**Action:** SSH to cluster and run:
```bash
kubectl get nodes -o wide
kubectl get node -o jsonpath='{.items[0].spec.providerID}'
```

**Expected:**
- [ ] Single node, `Ready`, role `control-plane`
- [ ] Version: `v1.35.7+k3s1`
- [ ] ProviderID: `aws:///us-east-1a/<instance-id>` (not `k3s://`)

---

## Test 3: All System Pods Running

**Action:**
```bash
kubectl get pods -A
```

**Expected (19 pods, 0 restarts):**
- [ ] `aws-cloud-controller-manager` — 1/1 Running
- [ ] `aws-iam-authenticator` — 1/1 Running
- [ ] `aws-node` (VPC CNI) — 2/2 Running
- [ ] `cert-manager` (3 pods) — all Running
- [ ] `ecp-workload-identity-webhook` — 1/1 Running
- [ ] `express-compute-auth-proxy` — 1/1 Running
- [ ] `eks-pod-identity-agent` — 1/1 Running
- [ ] `ebs-csi-controller` — 5/5 Running
- [ ] `ebs-csi-node` — 3/3 Running
- [ ] `karpenter` — 1/1 Running
- [ ] `ecp-karpenter-support` — 1/1 Running
- [ ] `kubelet-csr-approver` — 1/1 Running
- [ ] `cloudwatch-agent` — 1/1 Running
- [ ] `fluent-bit` — 1/1 Running
- [ ] `amazon-cloudwatch-observability-controller-manager` — 1/1 Running
- [ ] `coredns` — 1/1 Running
- [ ] `metrics-server` — 1/1 Running
- [ ] `local-path-provisioner` — 1/1 Running

---

## Test 4: Storage — gp3 StorageClass

**Action:**
```bash
kubectl get storageclass
```

**Expected:**
- [ ] `gp3 (default)` — provisioner `ebs.csi.aws.com`, `WaitForFirstConsumer`

---

## Test 5: Karpenter NodePool Setup

**Action:**
```bash
sudo bash /opt/k3s-xpress/cluster-setup/karpenter/configure-nodepools.sh
kubectl get nodepools,ec2nodeclasses
```

**Expected:**
- [ ] Script auto-detects k3s (not EKS-D)
- [ ] Instance profile: `ecp-tenant-<id>-ir`
- [ ] Service CIDR: `10.43.0.0/16`
- [ ] CA cert from `/var/lib/rancher/k3s/server/tls/server-ca.crt`
- [ ] NodePool: `Ready: True`
- [ ] EC2NodeClass: `Ready: True`

---

## Test 6: Karpenter Worker Launch + EBS Test Workload

**Action:**
```bash
kubectl apply -f /opt/k3s-xpress/cluster-setup/karpenter/ebs-test-workload.yaml
# Wait ~2 min for Karpenter to launch a worker
kubectl get nodes -o wide
kubectl get nodeclaims
kubectl get pods -l app=test-spot-workload -o wide
kubectl get pvc
```

**Expected:**
- [ ] Karpenter creates a NodeClaim (spot, arm64)
- [ ] Worker instance launched (EKS Optimized AMI)
- [ ] Worker authenticates via aws-iam-authenticator
- [ ] Worker CSR auto-approved by kubelet-csr-approver
- [ ] Worker node becomes `Ready`
- [ ] VPC CNI `aws-node` pod Running (2/2) on worker
- [ ] 3 test pods Running on the worker node with VPC-native IPs
- [ ] 3 PVCs Bound on gp3 EBS volumes

---

## Test 7: Cleanup

**Action:**
```bash
kubectl delete -f /opt/k3s-xpress/cluster-setup/karpenter/ebs-test-workload.yaml
kubectl delete nodepool default
kubectl delete ec2nodeclass default
# Wait for Karpenter to terminate the worker
kubectl get nodes  # should show only control plane
```

Then:
```bash
ecp delete-cluster k3s-acceptance
```

**Expected:**
- [ ] Worker terminated by Karpenter
- [ ] Cluster deleted
- [ ] No orphaned resources (SG, EBS, IAM, subnets, EIPs, secrets, SQS)

---

## Test Results

| Test | Status | Notes |
|------|--------|-------|
| 1. Cluster Creation | | |
| 2. Node Verification | | |
| 3. System Pods | | |
| 4. Storage | | |
| 5. Karpenter NodePool | | |
| 6. Worker + EBS Workload | | |
| 7. Cleanup | | |
