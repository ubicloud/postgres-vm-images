#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing build dependencies ==="

# Refresh package indexes
apt-get update

# Install build tools
apt-get install -y golang-go cmake

# Install Python and PostgreSQL development packages for all versions
apt-get install -y python3 python3-pip postgresql-server-dev-16 postgresql-server-dev-17 postgresql-server-dev-18

# Create symlink for python if needed (may already exist)
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true

echo "=== Building and installing WAL-G ==="

# Clone and build WAL-G
mkdir -p /var/wal-g
cd /var/wal-g
git init
git remote add origin https://github.com/wal-g/wal-g.git
git fetch origin --depth 1 cf1ce0f5b69048e31d740b508a79d8294707e339
git reset --hard FETCH_HEAD
make deps
make pg_build
GOBIN=/usr/bin make pg_install
make build_client
cp bin/walg-daemon-client /usr/bin/walg-daemon-client

echo "=== Building and installing pguint extension ==="

# Clone and build pguint for each PostgreSQL version
cd /tmp
git clone https://github.com/petere/pguint.git
cd pguint

# Build for PG 16
make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config
make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config install
make clean

# Build for PG 17
make PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config
make PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config install
make clean

# Build for PG 18
make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config
make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config install

# Clean up
cd /tmp
rm -rf pguint

echo "=== Installing monitoring tools ==="

# Install Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.53.0/prometheus-2.53.0.linux-amd64.tar.gz -P /tmp
tar -xzvf /tmp/prometheus-2.53.0.linux-amd64.tar.gz -C /tmp
cp /tmp/prometheus-2.53.0.linux-amd64/prometheus /usr/bin/prometheus
chown prometheus:prometheus /usr/bin/prometheus
chmod 100 /usr/bin/prometheus

# Install node_exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz -P /tmp
tar -xzvf /tmp/node_exporter-1.8.1.linux-amd64.tar.gz -C /tmp
cp /tmp/node_exporter-1.8.1.linux-amd64/node_exporter /usr/bin/node_exporter
chown prometheus:prometheus /usr/bin/node_exporter
chmod 100 /usr/bin/node_exporter

# Install postgres_exporter
wget https://github.com/prometheus-community/postgres_exporter/releases/download/v0.15.0/postgres_exporter-0.15.0.linux-amd64.tar.gz -P /tmp
tar -xzvf /tmp/postgres_exporter-0.15.0.linux-amd64.tar.gz -C /tmp
cp /tmp/postgres_exporter-0.15.0.linux-amd64/postgres_exporter /usr/bin/postgres_exporter
chown ubi_monitoring:ubi_monitoring /usr/bin/postgres_exporter
chmod 100 /usr/bin/postgres_exporter

echo "=== Installing systemd service files ==="

# Copy systemd unit files
cp /tmp/assets/prometheus.service /etc/systemd/system/prometheus.service
cp /tmp/assets/node_exporter.service /etc/systemd/system/node_exporter.service
cp /tmp/assets/postgres_exporter.service /etc/systemd/system/postgres_exporter.service
cp /tmp/assets/wal-g.service /etc/systemd/system/wal-g.service

# Copy postgres_exporter queries
mkdir -p /usr/local/share/postgresql
cp /tmp/assets/postgres_exporter_queries.yaml /usr/local/share/postgresql/postgres_exporter_queries.yaml

# Reload systemd to recognize new services
systemctl daemon-reload

echo "=== Setup 02 complete ==="
