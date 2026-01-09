#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== Building and installing WAL-G ==="

# Build WAL-G from source
cd /usr/local/src/wal-g
make deps
make pg_build
GOBIN=/usr/bin make pg_install
make build_client
cp bin/walg-daemon-client /usr/bin/walg-daemon-client

echo "=== Building and installing pguint extension ==="

# Build pguint for each PostgreSQL version from pre-downloaded source
cd /usr/local/src/pguint

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

cd /

echo "=== Installing monitoring tools from local binaries ==="

cd /tmp/downloads/binaries

# Install Prometheus
tar -xzvf prometheus-2.53.0.linux-amd64.tar.gz
cp prometheus-2.53.0.linux-amd64/prometheus /usr/bin/prometheus
chown prometheus:prometheus /usr/bin/prometheus
chmod 100 /usr/bin/prometheus

# Install node_exporter
tar -xzvf node_exporter-1.8.1.linux-amd64.tar.gz
cp node_exporter-1.8.1.linux-amd64/node_exporter /usr/bin/node_exporter
chown prometheus:prometheus /usr/bin/node_exporter
chmod 100 /usr/bin/node_exporter

# Install postgres_exporter
tar -xzvf postgres_exporter-0.15.0.linux-amd64.tar.gz
cp postgres_exporter-0.15.0.linux-amd64/postgres_exporter /usr/bin/postgres_exporter
chown ubi_monitoring:ubi_monitoring /usr/bin/postgres_exporter
chmod 100 /usr/bin/postgres_exporter

cd /

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
echo "WAL-G installed, pguint extension installed for PG 16/17/18, monitoring tools configured"
