# Fix: Karpenter interruption queue name mismatch (both k3s and EKS-D)

## Problem

Karpenter's `interruption` controller fails continuously on every provisioned
cluster (both k3s-Xpress and EKS-D):

```
"message":"failed to create valid sqs provider", "controller":"interruption",
"aws-operation-name":"GetQueueUrl", "aws-status-code":400,
"error":"... AWS.SimpleQueueService.NonExistentQueue: The specified queue
does not exist."
```

This repeats roughly every 17 minutes (the controller's resync interval) for
the lifetime of the cluster.

## Root Cause

The SQS interruption queue is created dynamically by the control plane
Lambda provisioner (`express-compute-control-plane`,
`TenantProvisioningService.createInterruptionQueue()`), named via
`TenantNaming.queueName(tenantId)`:

```
ecp-tenant-{tenantId}        e.g. ecp-tenant-e404823a
```

But both Karpenter install scripts in this repo configure the Helm chart
with the **cluster's display name** instead — no prefix, wrong identifier:

- `cluster-setup/15-install-karpenter.sh` (EKS-D):
  `--set settings.interruptionQueue=${CLUSTER_NAME}`
- `cluster-setup/k3s/install-karpenter.sh` (k3s):
  `--set settings.interruptionQueue="${CLUSTER_NAME}"`

`CLUSTER_NAME` (e.g. `k3s-ondemand-1791764741`) is a human-readable name
chosen at cluster creation; it is never used as part of the queue name on
the control-plane side. The queue Karpenter looks for
(`k3s-ondemand-1791764741`) never existed — the real queue
(`ecp-tenant-e404823a`) does, under a completely different name.

Both scripts already have `TENANT_ID` available (sourced from
`cluster.env` / passed as a script argument), so the fix only requires
pointing at the right variable with the right prefix.

## Impact

Low on steady-state cluster health — missing interruption handling means
Karpenter won't gracefully drain/cordon nodes ahead of a Spot interruption
or rebalance recommendation; pods on an interrupted Spot instance would be
rescheduled reactively (after the 2-minute AWS termination notice expires)
rather than proactively. No impact on on-demand-only node pools. No impact
observed on cluster stability — the failing reconciler retries harmlessly.

## Verified Fix (live test on deployed cluster)

Re-ran the Karpenter Helm install with the corrected queue name on a live
k3s-ondemand tenant cluster:

```bash
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.13.0 --namespace kube-system --reuse-values \
  --set settings.interruptionQueue="ecp-tenant-${TENANT_ID}" \
  --wait --timeout=120s
```

Result: pod restarted cleanly (`1/1 Ready`), zero SQS/interruption errors
over a 3+ minute observation window (previously errored almost immediately
on every controller startup). Existing nodes and workloads unaffected by
the restart.

## Permanent Fix

Change the `--set settings.interruptionQueue=...` value in both scripts
from `${CLUSTER_NAME}` to `"ecp-tenant-${TENANT_ID}"`, matching
`TenantNaming.queueName()` on the control-plane side exactly.
