# AMI Signature Verification

Every EKS-D-Xpress AMI is signed with an RSA-4096 KMS key after it is built.
The public key is committed to this repository so you can verify any AMI
without needing access to our AWS account.

## Prerequisites

- AWS CLI configured with **read-only** access to SSM in `us-east-1`
  (`ssm:GetParameter` on `arn:aws:ssm:us-east-1:864899852480:parameter/eks-d-xpress/*`)
- `openssl` (any modern version)
- `python3`

## Verify an AMI

```bash
git clone https://github.com/codriverlabs/eks-d-xpress.git
cd eks-d-xpress

AWS_REGION=us-east-1 ./ami-builder/scripts/verify-ami.sh \
  --ami-id  <AMI_ID>   \
  --arch    arm64      \   # or x86_64
  --k8s     1.35       \
  --version <VERSION>
```

Expected output on success:
```
✓ Signature VALID — ami-0d6cfeff13291c39e (arm64, k8s 1.35, version 20260611-0156)
```

### Finding the AMI ID and version

| Source | Command |
|--------|---------|
| AWS Console | EC2 → AMIs → search `eks-d-xpress` → owned by account `864899852480` |
| AWS CLI | `aws ec2 describe-images --owners 864899852480 --filters "Name=name,Values=eks-d-xpress-arm64-*" --query "sort_by(Images,&CreationDate)[-1].{ID:ImageId,Name:Name}"` |
| AMI tag | The `Name` tag on the AMI is `eks-d-xpress-<arch>-<VERSION>` |

The `VERSION` is the `<DATE>-<TIME>` suffix in the AMI name, e.g. `20260611-0156`.

## How verification works

The build pipeline creates a JSON attestation for each AMI:

```json
{
  "ami_id":             "ami-0d6cfeff13291c39e",
  "arch":               "arm64",
  "ami_version":        "20260611-0156",
  "kubernetes_version": "1.35",
  "timestamp":          "2026-06-11T02:02:09.123456Z"
}
```

This is signed with `RSASSA_PKCS1_V1_5_SHA_256` using a KMS RSA-4096 key.
The signature is stored in our AWS SSM Parameter Store. The `verify-ami.sh`
script fetches the signature, reconstructs the attestation, and verifies it
against `ami-builder/eks-d-xpress-ami-signing.pub.pem`.

The timestamp is also stamped as a `SigningTimestamp` tag on the AMI itself,
so you can inspect it independently:

```bash
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=<AMI_ID>" \
  --query "Tags[?Key=='SigningTimestamp' || Key=='Signed' || Key=='SigningKeyArn']"
```

## Public key fingerprint

```
ami-builder/eks-d-xpress-ami-signing.pub.pem
SHA-256: 99fd42ec9397f28a5e99d6374f390d474562f64ae3ac570776b21320a2ec43ad
```

To compute it yourself:
```bash
openssl pkey -pubin -in ami-builder/eks-d-xpress-ami-signing.pub.pem \
  -outform DER | openssl dgst -sha256
```
