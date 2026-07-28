# Quick Start: Self-Managed Clusters (Workload Identity)

Add AWS Workload Identity (Pod Identity) to any existing Kubernetes cluster — k3s, microk8s, EKS-D, or standard kubeadm clusters.

Pods get temporary IAM credentials automatically, without node-level IAM roles or IRSA annotation complexity.

---

## Prerequisites

- A running Kubernetes cluster with `kubectl` access
- AWS credentials with permissions to the Express Compute control plane
- `helm` v3 installed
- `ecp` CLI on PATH (or inside the bundle container)

---

## 1. Deploy the Control Plane (one-time, per AWS account)

If not already done:

```bash
docker run --rm -it \
  --name express-compute-installer \
  -v ~/.aws:/root/.aws:ro \
  -e AWS_PROFILE="${AWS_PROFILE:-default}" \
  -e AWS_REGION="${AWS_REGION:-us-east-1}" \
  --entrypoint bash \
  ghcr.io/codriverlabs/express-compute-bundle:latest

# Inside the container — self-managed mode skips infra + AMI registration
./deploy.sh deploy --deployment-mode self-managed --region us-east-1
```

---

## 2. Register Your Cluster

Register your existing cluster with the Express Compute control plane. This
publishes the cluster's OIDC/JWKS configuration so AWS STS can validate pod tokens.

```bash
# Option A: auto-discover JWKS from kubeconfig (recommended)
ecp create-cluster my-k3s --kubeconfig ~/.kube/config

# Option B: explicit JWKS file
kubectl get --raw /openid/v1/jwks > /tmp/jwks.json
ecp create-cluster my-k3s \
  --issuer "https://kubernetes.default.svc" \
  --jwks-file /tmp/jwks.json

# Option C: JWKS via public URL (if your cluster API is internet-reachable)
ecp create-cluster my-k3s \
  --issuer "https://my-cluster.example.com" \
  --jwks-uri "https://my-cluster.example.com/openid/v1/jwks"
```

Verify registration:

```bash
ecp describe-cluster my-k3s
```

---

## 3. Install Workload Identity Components

Download the installer from the latest release and verify its checksum:

```bash
VERSION="1.0.0-rc11"  # replace with your target version

curl -fsSL "https://github.com/codriverlabs/express-compute-platform/releases/download/v${VERSION}/install-ecp-workload-identity.sh" \
  -o install-ecp-workload-identity.sh

curl -fsSL "https://github.com/codriverlabs/express-compute-platform/releases/download/v${VERSION}/checksums.txt" \
  -o checksums.txt

# Verify checksum
grep install-ecp-workload-identity.sh checksums.txt | sha256sum --check
chmod +x install-ecp-workload-identity.sh
```

Run the installer:

```bash
export CLUSTER_NAME="my-k3s"
export AWS_REGION="us-east-1"
export ECP_CONTROL_PLANE_VERSION="${VERSION}"

./install-ecp-workload-identity.sh
```

The script installs:
1. **cert-manager** — TLS certificates for webhook (skipped if already present)
2. **ecp-auth-proxy** — TokenReview + credential forwarding
3. **ecp-workload-identity-webhook** — mutating webhook that injects AWS credentials into pods
4. **eks-pod-identity-agent** — DaemonSet intercepting the credential endpoint (169.254.170.23)

---

## 4. Create a Workload Identity (Pod Identity Association)

Bind a Kubernetes service account to an IAM role:

```bash
ecp create-association \
  --cluster-name my-k3s \
  --namespace default \
  --service-account my-app \
  --role-arn arn:aws:iam::123456789012:role/MyAppRole
```

---

## 5. Test It

Deploy a pod using that service account — it should get AWS credentials automatically:

```bash
kubectl run aws-test --image=amazon/aws-cli:latest --rm -it \
  --overrides='{"spec":{"serviceAccountName":"my-app"}}' \
  -- sts get-caller-identity
```

Expected output:

```json
{
    "UserId": "AROA...:my-k3s-default-my-app",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/MyAppRole/my-k3s-default-my-app"
}
```

---

## 6. Refresh JWKS (After Certificate Rotation)

If your cluster's service account signing key rotates:

```bash
ecp update-cluster my-k3s --refresh-jwks --kubeconfig ~/.kube/config
```

---

## Uninstall

```bash
helm uninstall eks-pod-identity-agent -n kube-system
helm uninstall express-compute-workload-identity-webhook -n kube-system
helm uninstall express-compute-auth-proxy -n kube-system

# Deregister from control plane
ecp delete-cluster my-k3s
```

---

## Troubleshooting

**Pod not getting credentials**
```bash
# Check webhook is injecting the projected token volume
kubectl get pod <pod-name> -o yaml | grep -A5 projected

# Check agent is running
kubectl get pods -n kube-system -l app=eks-pod-identity-agent

# Check auth-proxy logs
kubectl logs -n kube-system -l app.kubernetes.io/name=express-compute-auth-proxy
```

**Cluster registration failed**
```bash
# Verify JWKS is accessible
kubectl get --raw /openid/v1/jwks | python3 -m json.tool

# Check describe-cluster output
ecp describe-cluster my-k3s
```

**ECR pull failures (eks-pod-identity-agent image)**
```bash
# The installer creates an ECR pull secret — check it exists
kubectl get secret ecr-pod-identity-agent -n kube-system

# If expired, re-run the installer or manually refresh:
kubectl create secret docker-registry ecr-pod-identity-agent \
  --namespace kube-system \
  --docker-server=602401143452.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region us-west-2)" \
  --dry-run=client -o yaml | kubectl apply -f -
```
