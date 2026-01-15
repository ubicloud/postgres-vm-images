#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== [standard/setup.sh] Standard flavor setup ==="

# Detect architecture for CloudWatch Agent
ARCH=$(uname -m)
case $ARCH in
  x86_64)  CW_ARCH="amd64" ;;
  aarch64) CW_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Install CloudWatch Agent (for AWS AMI compatibility)
echo "[standard/setup.sh] Installing CloudWatch Agent (architecture: $CW_ARCH)..."
curl -O https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/${CW_ARCH}/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm -f amazon-cloudwatch-agent.deb

# Install and run ClamAV scan
echo "[standard/setup.sh] Installing ClamAV..."
apt-get update
apt-get install -y clamav clamav-freshclam

echo "[standard/setup.sh] Updating ClamAV virus database..."
systemctl stop clamav-freshclam.service || true
freshclam

echo "[standard/setup.sh] Running ClamAV scan on system binaries..."
mkdir -p /tmp/clamav
clamscan --quiet -r /usr/bin /usr/sbin /lib /lib64 /usr/lib /etc --log=/tmp/clamav/scan.log -i || true
echo "[standard/setup.sh] ClamAV scan results:"
cat /tmp/clamav/scan.log || true

echo "=== [standard/setup.sh] Complete ==="
