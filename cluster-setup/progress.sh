#!/bin/bash
# progress.sh — SQS FIFO progress reporting for Express Compute boot scripts.
# Source this file from workstation-boot.sh or any boot script.
#
# Requires: TENANT_ID, AWS_REGION, PROGRESS_QUEUE_URL (from cluster.env)
#
# The instance profile has sqs:SendMessage scoped to the per-tenant progress
# queue ARN. No additional credentials are needed — uses instance profile directly.
#
# The queue is ephemeral: created by the provisioning Lambda, deleted by the
# SSE Lambda on terminal state (ready/failed). If the queue no longer exists,
# progress reporting silently stops (provisioning already completed/failed).

# Send a progress event to the per-tenant SQS FIFO queue.
# Usage: update_progress <state> <phase> <progress_percent>
update_progress() {
  local state=$1 phase=$2 progress=$3

  # Skip if TENANT_ID or PROGRESS_QUEUE_URL not set (e.g. manual run without cluster.env)
  [ -z "${TENANT_ID:-}" ] && return 0
  [ -z "${PROGRESS_QUEUE_URL:-}" ] && return 0

  aws sqs send-message \
    --queue-url "${PROGRESS_QUEUE_URL}" \
    --message-group-id "${TENANT_ID}" \
    --message-deduplication-id "${TENANT_ID}-${progress}" \
    --message-body "{\"tenantId\":\"${TENANT_ID}\",\"state\":\"${state}\",\"phase\":\"${phase}\",\"progress\":${progress}}" \
    --region "${AWS_REGION}" 2>/dev/null || true
}

# Report failure and exit.
# Usage: fail "error message"
fail() {
  local msg=$1

  [ -z "${TENANT_ID:-}" ] && { echo "FATAL: $msg"; exit 1; }
  [ -z "${PROGRESS_QUEUE_URL:-}" ] && { echo "FATAL: $msg"; exit 1; }

  aws sqs send-message \
    --queue-url "${PROGRESS_QUEUE_URL}" \
    --message-group-id "${TENANT_ID}" \
    --message-deduplication-id "${TENANT_ID}-failed" \
    --message-body "{\"tenantId\":\"${TENANT_ID}\",\"state\":\"failed\",\"phase\":\"${msg}\",\"progress\":0}" \
    --region "${AWS_REGION}" 2>/dev/null || true

  exit 1
}

# Report ready state.
# Usage: report_ready
report_ready() {
  [ -z "${TENANT_ID:-}" ] && return 0
  [ -z "${PROGRESS_QUEUE_URL:-}" ] && return 0

  aws sqs send-message \
    --queue-url "${PROGRESS_QUEUE_URL}" \
    --message-group-id "${TENANT_ID}" \
    --message-deduplication-id "${TENANT_ID}-100" \
    --message-body "{\"tenantId\":\"${TENANT_ID}\",\"state\":\"ready\",\"phase\":\"Cluster ready\",\"progress\":100}" \
    --region "${AWS_REGION}" 2>/dev/null || true
}
