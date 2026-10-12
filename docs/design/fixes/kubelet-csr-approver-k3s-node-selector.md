# Fix: kubelet-csr-approver stuck Pending on k3s clusters

## Problem

`kubelet-csr-approver` (deployed by `cluster-setup/k3s/install-addons.sh` and
`cluster-setup/11b-install-kubelet-csr-approver.sh` for EKS-D) never schedules
on k3s-Xpress clusters. The pod sits in `Pending` indefinitely:

```
Warning  FailedScheduling  default-scheduler  0/1 nodes are available:
1 node(s) didn't match Pod's node affinity/selector.
```

## Root Cause

`cluster-setup/manifests/kubelet-csr-approver.yaml` hardcodes:

```yaml
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
```

This selector requires an **exact match** on an empty string value, which is
correct for kubeadm-based clusters (EKS-D), where the control-plane label is
applied with no value.

**k3s does not follow this convention.** k3s automatically labels its
server/control-plane nodes with:

```
node-role.kubernetes.io/control-plane=true
node-role.kubernetes.io/master=true
```

(value `"true"`, not empty). Since `nodeSelector` only supports exact
key=value equality, `""` never matches `"true"`, and the pod is permanently
unschedulable on k3s — not transient, does not self-resolve.

This also means the comparison table in `docs/design/k3s-vpc-cni-karpenter.md`
section 5.5 ("CSR auto-approver | ... | ✓ same (kubelet-csr-approver)") is
incorrect as written — the manifest is shared, but requires a
distribution-aware node selector to actually work on both.

## Impact

- Low on existing single-node clusters that already finished initial
  bootstrap (kubelet client/serving certs for the first node were already
  approved before this component mattered).
- Real impact: any **future** CSR on a k3s cluster — kubelet cert rotation,
  or a second/worker node joining via Karpenter — has nothing to
  auto-approve it, since this is the one component responsible for that
  signer pair (`kube-apiserver-client-kubelet`, `kubelet-serving`).

## Verified Fix (live test on deployed cluster)

Patched the running Deployment on a provisioned k3s-ondemand tenant cluster:

```bash
kubectl patch deployment -n kube-system kubelet-csr-approver --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/nodeSelector",
       "value":{"node-role.kubernetes.io/control-plane":"true"}}]'
```

Result: pod went from `0/1 Pending` → `1/1 Running` immediately on rollout.
Confirms the label-value mismatch is the sole blocker.

## Permanent Fix

Rather than hardcoding either `""` (EKS-D) or `"true"` (k3s) — which would
just move the bug to the other distribution — replace the plain
`nodeSelector` with a `nodeAffinity` using the `Exists` operator, which
matches the label regardless of its value:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: node-role.kubernetes.io/control-plane
              operator: Exists
```

This works identically for EKS-D (`=""`) and k3s (`="true"`) without needing
distribution-specific manifest variants or install-script patching.

## Follow-up

- Correct the claim in `docs/design/k3s-vpc-cni-karpenter.md` section 5.5.
