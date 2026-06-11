#!/usr/bin/env bash
# verify-ami.sh — verify an EKS-D-Xpress AMI attestation signature.
#
# Reconstructs the attestation JSON (same format used by sign-ami.sh),
# fetches the signature from SSM, and verifies it against the published
# RSA-4096 public key bundled in this repo.
#
# Usage:
#   AWS_REGION=us-east-1 ./ami-builder/scripts/verify-ami.sh \
#     --ami-id     ami-0abc1234def56789 \
#     --arch       arm64 \
#     --k8s        1.35 \
#     --version    20260611-0156
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBKEY="${SCRIPT_DIR}/../eks-d-xpress-ami-signing.pub.pem"
AWS_REGION="${AWS_REGION:?set AWS_REGION}"

AMI_ID="" ARCH="" K8S_VERSION="" AMI_VERSION=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --ami-id)   AMI_ID=$2;      shift 2 ;;
    --arch)     ARCH=$2;        shift 2 ;;
    --k8s)      K8S_VERSION=$2; shift 2 ;;
    --version)  AMI_VERSION=$2; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "${AMI_ID}" && -n "${ARCH}" && -n "${K8S_VERSION}" && -n "${AMI_VERSION}" ]] || {
  echo "ERROR: --ami-id, --arch, --k8s, and --version are required" >&2; exit 1
}

python3 - <<PYEOF
import json, sys, subprocess, base64, tempfile, os

ami_id, arch, k8s, ami_ver, region, pubkey = \
    "${AMI_ID}", "${ARCH}", "${K8S_VERSION}", "${AMI_VERSION}", "${AWS_REGION}", "${PUBKEY}"

# 1. Fetch signature from SSM (stored as base64 text)
sig_b64 = subprocess.check_output([
    "aws", "ssm", "get-parameter",
    "--region", region,
    "--name", f"/eks-d-xpress/infra/ami/{arch}/{k8s}/signature",
    "--query", "Parameter.Value", "--output", "text",
]).decode().strip()

# 2. Reconstruct attestation — must match sign-ami.sh exactly (sort_keys=True)
# Timestamp is embedded in the signature; we must fetch it from SSM tags or AMI tags.
# sign-ami.sh tags the AMI with SigningKeyArn but not the timestamp, so we recover
# it from the AMI description tag added at signing time.
tags_raw = subprocess.check_output([
    "aws", "ec2", "describe-tags",
    "--region", region,
    "--filters", f"Name=resource-id,Values={ami_id}",
    "--query", "Tags[?Key=='SigningTimestamp'].Value",
    "--output", "text",
]).decode().strip()

if not tags_raw:
    print("ERROR: AMI is missing SigningTimestamp tag — cannot reconstruct attestation.", file=sys.stderr)
    print("The AMI may have been built before verify support was added.", file=sys.stderr)
    sys.exit(1)

attestation = json.dumps({
    "ami_id":             ami_id,
    "arch":               arch,
    "kubernetes_version": k8s,
    "ami_version":        ami_ver,
    "timestamp":          tags_raw,
}, sort_keys=True)

# 3. Verify signature with OpenSSL
with tempfile.TemporaryDirectory() as d:
    msg_file = os.path.join(d, "attestation.json")
    sig_file = os.path.join(d, "attestation.sig")
    with open(msg_file, "w") as f: f.write(attestation)
    with open(sig_file, "wb") as f: f.write(base64.b64decode(sig_b64))

    result = subprocess.run([
        "openssl", "dgst", "-sha256", "-verify", pubkey,
        "-sigopt", "rsa_padding_mode:pkcs1",
        "-signature", sig_file, msg_file,
    ], capture_output=True, text=True)

if result.returncode == 0:
    print(f"✓ Signature VALID — {ami_id} ({arch}, k8s {k8s}, version {ami_ver})")
else:
    print(f"✗ Signature INVALID — {ami_id}")
    print(result.stderr, file=sys.stderr)
    sys.exit(1)
PYEOF
