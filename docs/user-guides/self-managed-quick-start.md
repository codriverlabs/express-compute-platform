# Quick Start: Self-Managed Clusters (Workload Identity)

Add AWS Workload Identity (Pod Identity) to any existing Kubernetes cluster — k3s, microk8s, EKS-D, or standard kubeadm clusters.

Pods get temporary IAM credentials automatically, without node-level IAM roles or IRSA annotation complexity.

---

## Prerequisites

- A running Kubernetes cluster with `kubectl` access
- AWS CLI configured with permissions to create IAM roles and S3 buckets
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
# Auto-discover JWKS from kubeconfig (recommended)
ecp create-cluster my-k3s --kubeconfig ~/.kube/config
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
BASE_URL="https://github.com/codriverlabs/express-compute-platform/releases/download/v${VERSION}"

curl -fsSL "${BASE_URL}/install-ecp-workload-identity.sh" \
  -o install-ecp-workload-identity.sh

curl -fsSL "${BASE_URL}/install-ecp-workload-identity.sh.sha256" \
  -o install-ecp-workload-identity.sh.sha256

sha256sum --check install-ecp-workload-identity.sh.sha256
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

## 4. Create an IAM Role and S3 Bucket for Testing

> **Full IAM reference:** See [IAM Role Setup for Express Compute Workload Identity](https://github.com/codriverlabs/express-compute-control-plane/blob/main/docs/user-guides/iam/iam-role-setup.md)
> for session tags, manual trust policies, dual-use roles (EKS + ECP), and ABAC patterns.

Create a test S3 bucket and an IAM role that allows access to it:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="ecp-test-${ACCOUNT_ID}-${AWS_REGION}"

# Create test bucket
aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"

# Create IAM policy
cat > /tmp/ecp-test-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name ecp-test-s3-access \
  --policy-document file:///tmp/ecp-test-policy.json

# Create IAM role with trust policy for Express Compute
# Option A (recommended): tag the role so ECP auto-configures trust policy
cat > /tmp/ecp-test-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": []
}
EOF

aws iam create-role \
  --role-name ecp-test-s3-role \
  --assume-role-policy-document file:///tmp/ecp-test-trust.json

# Tag the role — Express Compute will auto-configure the trust policy
# when you create the association in the next step
aws iam tag-role \
  --role-name ecp-test-s3-role \
  --tags Key=ecp-managed,Value=true

aws iam attach-role-policy \
  --role-name ecp-test-s3-role \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ecp-test-s3-access"
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ecp-test-s3-access"
```

---

## 5. Create the Service Account and Association

```bash
# Create a Kubernetes service account
kubectl create serviceaccount ecp-test-sa -n default

# Bind it to the IAM role via Express Compute
ecp create-association \
  --cluster-name my-k3s \
  --namespace default \
  --service-account ecp-test-sa \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/ecp-test-s3-role"
```

---

## 6. Test — Pod Gets AWS Credentials Automatically

Run a pod with the test service account. It will receive AWS credentials via the
injected projected token and the pod identity agent:

```bash
# Verify identity
kubectl run aws-test --image=public.ecr.aws/aws-cli/aws-cli:latest --rm -it \
  --restart=Never \
  --overrides='{"spec":{"serviceAccountName":"ecp-test-sa"}}' \
  -- sts get-caller-identity
```

Expected output:

```json
{
    "UserId": "AROA...:my-k3s-default-ecp-test-sa",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/ecp-test-s3-role/my-k3s-default-ecp-test-sa"
}
```

Test S3 access:

```bash
# Upload a test file
kubectl run s3-write --image=public.ecr.aws/aws-cli/aws-cli:latest --rm -it \
  --restart=Never \
  --overrides='{"spec":{"serviceAccountName":"ecp-test-sa"}}' \
  -- s3 cp - "s3://${BUCKET_NAME}/hello.txt" <<< "Hello from Workload Identity!"

# Read it back
kubectl run s3-read --image=public.ecr.aws/aws-cli/aws-cli:latest --rm -it \
  --restart=Never \
  --overrides='{"spec":{"serviceAccountName":"ecp-test-sa"}}' \
  -- s3 cp "s3://${BUCKET_NAME}/hello.txt" -
```

---

## 7. Refresh JWKS (After Certificate Rotation)

If your cluster's service account signing key rotates:

```bash
ecp update-cluster my-k3s --refresh-jwks --kubeconfig ~/.kube/config
```

---

## Cleanup

```bash
# Delete test pod identity association
ecp delete-association --cluster-name my-k3s --association-id <id-from-list>

# Remove Kubernetes resources
kubectl delete serviceaccount ecp-test-sa -n default

# Remove Workload Identity components
helm uninstall eks-pod-identity-agent -n kube-system
helm uninstall express-compute-workload-identity-webhook -n kube-system
helm uninstall express-compute-auth-proxy -n kube-system

# Deregister cluster
ecp delete-cluster my-k3s

# Clean up AWS resources
aws s3 rb "s3://${BUCKET_NAME}" --force
aws iam detach-role-policy --role-name ecp-test-s3-role \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ecp-test-s3-access"
aws iam delete-role --role-name ecp-test-s3-role
aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ecp-test-s3-access"
```

---

## Troubleshooting

**Pod not getting credentials**
```bash
# Check webhook is injecting the projected token volume
kubectl get pod <pod-name> -o yaml | grep -A5 projected

# Check agent is running on each node
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

**AssumeRole fails with "Not authorized to perform sts:AssumeRole"**
```bash
# Verify the role has the ecp-managed tag
aws iam list-role-tags --role-name ecp-test-s3-role

# Verify the trust policy was auto-configured (should reference ECPCredentialBroker)
aws iam get-role --role-name ecp-test-s3-role --query Role.AssumeRolePolicyDocument

# Verify the association exists
ecp list-associations --cluster-name my-k3s
```

**ECR pull failures (eks-pod-identity-agent image)**
```bash
# The installer creates an ECR pull secret — check it exists
kubectl get secret ecr-pod-identity-agent -n kube-system

# If expired (~12h), refresh manually:
kubectl create secret docker-registry ecr-pod-identity-agent \
  --namespace kube-system \
  --docker-server=602401143452.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region us-west-2)" \
  --dry-run=client -o yaml | kubectl apply -f -
```
