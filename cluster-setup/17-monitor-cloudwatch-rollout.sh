#!/bin/bash
set -e

echo "Verifying CloudWatch rollout..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=amazon-cloudwatch-agent \
  -n amazon-cloudwatch --timeout=60s 2>/dev/null \
  && echo "✓ CloudWatch agent healthy" \
  || echo "⚠ CloudWatch agent not ready — check: kubectl get pods -n amazon-cloudwatch"

kubectl get pods -n amazon-cloudwatch
