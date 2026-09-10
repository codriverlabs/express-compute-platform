#!/bin/bash
set -e

# Express Compute AMI Cleanup Script
# Deletes Express Compute AMIs owned by the current account.
#
# Usage:
#   ./cleanup-amis.sh              # k3s AMIs (default)
#   ./cleanup-amis.sh k3s          # k3s AMIs
#   ./cleanup-amis.sh eks-d        # EKS-D AMIs
#   ./cleanup-amis.sh all          # Both distributions

DISTRIBUTION="${1:-k3s}"

case "$DISTRIBUTION" in
  k3s)    FILTER="k3s-xpress-*"; LABEL="k3s-Xpress" ;;
  eks-d)  FILTER="express-compute-*"; LABEL="EKS-D" ;;
  all)    FILTER=""; LABEL="All Express Compute" ;;
  *)      echo "Usage: $0 [k3s|eks-d|all]"; exit 1 ;;
esac

echo "=========================================="
echo "${LABEL} AMI Cleanup"
echo "=========================================="

# Get AMIs — "all" mode matches both naming patterns
if [ "$DISTRIBUTION" = "all" ]; then
  AMIS=$(aws ec2 describe-images --owners self \
    --filters "Name=name,Values=express-compute-*,k3s-xpress-*" \
    --query "Images[*].{ImageId:ImageId,Name:Name,CreationDate:CreationDate}" --output json)
else
  AMIS=$(aws ec2 describe-images --owners self \
    --filters "Name=name,Values=${FILTER}" \
    --query "Images[*].{ImageId:ImageId,Name:Name,CreationDate:CreationDate}" --output json)
fi

if [ "$(echo "$AMIS" | jq length)" -eq 0 ]; then
  echo "No ${LABEL} AMIs found to delete."
  exit 0
fi

echo "Found ${LABEL} AMIs:"
echo "$AMIS" | jq -r '.[] | "\(.ImageId) - \(.Name) (\(.CreationDate))"'
echo ""

# Confirm deletion
read -p "Delete all these AMIs? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

echo ""
echo "Deleting AMIs and snapshots..."

TMPFILE=$(mktemp)

# Collect all AMI-snapshot mappings first
echo "$AMIS" | jq -r '.[].ImageId' | while read ami_id; do
  SNAPSHOTS=$(aws ec2 describe-images --image-ids "$ami_id" \
    --query "Images[0].BlockDeviceMappings[?Ebs].Ebs.SnapshotId" --output text | grep -v '^$' || true)
  echo "$ami_id:${SNAPSHOTS:-}" >> "$TMPFILE"
done

# Deregister all AMIs first
echo "$AMIS" | jq -r '.[].ImageId' | while read ami_id; do
  echo "Deregistering AMI: $ami_id"
  aws ec2 deregister-image --image-id "$ami_id"
done

# Then delete all snapshots
while IFS=':' read -r ami_id snapshots; do
  if [ -n "$snapshots" ]; then
    echo "Deleting snapshots for $ami_id: $snapshots"
    echo "$snapshots" | xargs -n1 aws ec2 delete-snapshot --snapshot-id
  fi
  echo "✓ Deleted $ami_id and associated snapshots"
done < "$TMPFILE"

rm -f "$TMPFILE"

echo ""
echo "✓ All ${LABEL} AMIs and snapshots deleted successfully!"
