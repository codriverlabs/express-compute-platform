#!/bin/bash
set -e

# Express Compute AMI Cleanup Script
# Deletes Express Compute AMIs owned by the current account.
#
# Usage:
#   ./cleanup-amis.sh                    # development k3s AMIs (default)
#   ./cleanup-amis.sh k3s                # development k3s AMIs
#   ./cleanup-amis.sh eks-d              # development EKS-D AMIs
#   ./cleanup-amis.sh all                # development AMIs (both distributions)
#   ./cleanup-amis.sh k3s ga             # GA k3s AMIs
#   ./cleanup-amis.sh all all            # ALL AMIs regardless of release stage

DISTRIBUTION="${1:-k3s}"
RELEASE_STAGE="${2:-development}"

case "$DISTRIBUTION" in
  k3s)    NAME_FILTER="k3s-xpress-*"; LABEL="k3s-Xpress" ;;
  eks-d)  NAME_FILTER="express-compute-*"; LABEL="EKS-D" ;;
  all)    NAME_FILTER=""; LABEL="All Express Compute" ;;
  *)      echo "Usage: $0 [k3s|eks-d|all] [development|staging|ga|all]"; exit 1 ;;
esac

LABEL="${LABEL} (${RELEASE_STAGE})"

echo "=========================================="
echo "${LABEL} AMI Cleanup"
echo "=========================================="

# Build filters
FILTERS=()
if [ "$DISTRIBUTION" = "all" ]; then
  FILTERS+=("Name=name,Values=express-compute-*,k3s-xpress-*")
else
  FILTERS+=("Name=name,Values=${NAME_FILTER}")
fi

if [ "$RELEASE_STAGE" != "all" ]; then
  FILTERS+=("Name=tag:Release,Values=${RELEASE_STAGE}")
fi

AMIS=$(aws ec2 describe-images --owners self \
  --filters "${FILTERS[@]}" \
  --query "Images[*].{ImageId:ImageId,Name:Name,CreationDate:CreationDate,Release:Tags[?Key=='Release']|[0].Value}" --output json)

if [ "$(echo "$AMIS" | jq length)" -eq 0 ]; then
  echo "No ${LABEL} AMIs found to delete."
  exit 0
fi

echo "Found AMIs:"
echo "$AMIS" | jq -r '.[] | "\(.ImageId) - \(.Name) [Release=\(.Release // "untagged")] (\(.CreationDate))"'
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
