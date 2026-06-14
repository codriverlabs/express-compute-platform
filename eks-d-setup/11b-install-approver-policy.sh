#!/bin/bash
set -e

# Deploy kubelet CSR auto-approver — replicates EKS control-plane CSR approval behavior.
# Approves kubernetes.io/kube-apiserver-client-kubelet (node joining) and
# kubernetes.io/kubelet-serving (serving certs for metrics-server etc.).
# Must run after kubeadm init (kubectl must be available).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KUBECTL_IMAGE="registry.k8s.io/kubectl:v1.32.0"
if [ -n "${ECR_REGISTRY:-}" ]; then
  KUBECTL_IMAGE="${ECR_REGISTRY}/registry-k8s-io/kubectl:v1.32.0"
fi

sed "s|KUBECTL_IMAGE_PLACEHOLDER|${KUBECTL_IMAGE}|" \
  "${SCRIPT_DIR}/manifests/kubelet-csr-approver.yaml" | kubectl apply -f -

echo "✓ kubelet-csr-approver deployed — node CSRs will be auto-approved"
