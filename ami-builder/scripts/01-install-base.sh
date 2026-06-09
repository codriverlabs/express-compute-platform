#!/bin/bash
set -e

echo "Updating system packages..."
sudo dnf update -y

# Disable update-motd — runs dnf updateinfo on every boot (~18s wasted)
echo "Disabling update-motd.service..."
sudo systemctl disable update-motd.service
sudo systemctl disable update-motd.timer 2>/dev/null || true

# Mask only the legacy ec2-net-utils v1 service — VPC CNI IPAMD handles ENI management.
# policy-routes@.service (v2) must remain active: IPAMD relies on it for per-interface
# policy routing rules for secondary IPs.
echo "Masking legacy ec2-net-utils..."
sudo systemctl mask ec2-net-utils.service 2>/dev/null || true

echo "✓ Base system updated"
