#!/bin/bash
set -e

echo "Updating system packages..."
sudo dnf update -y

# Disable update-motd — runs dnf updateinfo on every boot (~18s wasted)
echo "Disabling update-motd.service..."
sudo systemctl disable update-motd.service
sudo systemctl disable update-motd.timer 2>/dev/null || true

# Mask ec2-net-utils secondary ENI policy routing — VPC CNI owns all ENI management.
# Must be masked (not just disabled) so udev/systemd can't trigger it on ENI hotplug
# before the boot script reaches the CNI install step.
echo "Masking ec2-net-utils..."
sudo systemctl mask policy-routes@.service refresh-policy-routes@.timer 2>/dev/null || true

echo "✓ Base system updated"
