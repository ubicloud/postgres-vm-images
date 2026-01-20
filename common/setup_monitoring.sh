#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== [setup_monitoring.sh] Installing monitoring tools ==="

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
  x86_64)  PROM_ARCH="amd64" ;;
  aarch64) PROM_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

echo "[setup_monitoring.sh] Detected architecture: $ARCH (prometheus arch: $PROM_ARCH)"

# Install Prometheus
echo "[setup_monitoring.sh] Downloading Prometheus v2.53.0..."
wget https://github.com/prometheus/prometheus/releases/download/v2.53.0/prometheus-2.53.0.linux-${PROM_ARCH}.tar.gz -P /tmp
tar -xzvf /tmp/prometheus-2.53.0.linux-${PROM_ARCH}.tar.gz -C /tmp
cp /tmp/prometheus-2.53.0.linux-${PROM_ARCH}/prometheus /usr/bin/prometheus
chown prometheus:prometheus /usr/bin/prometheus
chmod 100 /usr/bin/prometheus

# Install node_exporter
echo "[setup_monitoring.sh] Downloading node_exporter v1.8.1..."
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-${PROM_ARCH}.tar.gz -P /tmp
tar -xzvf /tmp/node_exporter-1.8.1.linux-${PROM_ARCH}.tar.gz -C /tmp
cp /tmp/node_exporter-1.8.1.linux-${PROM_ARCH}/node_exporter /usr/bin/node_exporter
chown prometheus:prometheus /usr/bin/node_exporter
chmod 100 /usr/bin/node_exporter

# Install postgres_exporter
echo "[setup_monitoring.sh] Downloading postgres_exporter v0.15.0..."
wget https://github.com/prometheus-community/postgres_exporter/releases/download/v0.15.0/postgres_exporter-0.15.0.linux-${PROM_ARCH}.tar.gz -P /tmp
tar -xzvf /tmp/postgres_exporter-0.15.0.linux-${PROM_ARCH}.tar.gz -C /tmp
cp /tmp/postgres_exporter-0.15.0.linux-${PROM_ARCH}/postgres_exporter /usr/bin/postgres_exporter
chown ubi_monitoring:ubi_monitoring /usr/bin/postgres_exporter
chmod 100 /usr/bin/postgres_exporter

echo "=== [setup_monitoring.sh] Installing systemd service files ==="

# Copy systemd unit files
echo "[setup_monitoring.sh] Copying systemd unit files..."
cp /tmp/common/assets/prometheus.service /etc/systemd/system/prometheus.service
cp /tmp/common/assets/node_exporter.service /etc/systemd/system/node_exporter.service
cp /tmp/common/assets/postgres_exporter.service /etc/systemd/system/postgres_exporter.service
cp /tmp/common/assets/wal-g.service /etc/systemd/system/wal-g.service

# Copy postgres_exporter queries
mkdir -p /usr/local/share/postgresql
cp /tmp/common/assets/postgres_exporter_queries.yaml /usr/local/share/postgresql/postgres_exporter_queries.yaml

# Reload systemd to recognize new services
echo "[setup_monitoring.sh] Reloading systemd daemon..."
systemctl daemon-reload

# =============================================
# CloudWatch Agent (for AWS AMI compatibility)
# =============================================
echo "=== [setup_monitoring.sh] Installing CloudWatch Agent ==="

case $ARCH in
  x86_64)  CW_ARCH="amd64" ;;
  aarch64) CW_ARCH="arm64" ;;
esac

curl -O https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/${CW_ARCH}/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm -f amazon-cloudwatch-agent.deb

# =============================================
# ClamAV Security Scan
# =============================================
echo "=== [setup_monitoring.sh] Installing and running ClamAV scan ==="

apt-get update
apt-get install -y clamav clamav-freshclam

echo "[setup_monitoring.sh] Updating ClamAV virus database..."
systemctl stop clamav-freshclam.service || true
freshclam

echo "[setup_monitoring.sh] Running ClamAV scan on system binaries..."
mkdir -p /tmp/clamav
clamscan --quiet -r /usr/bin /usr/sbin /lib /lib64 /usr/lib /etc --log=/tmp/clamav/scan.log -i || true
echo "[setup_monitoring.sh] ClamAV scan results:"
cat /tmp/clamav/scan.log || true

echo "=== [setup_monitoring.sh] Complete ==="
