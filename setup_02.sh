#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

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

# Copy systemd unit files
cp /tmp/assets/prometheus.service /etc/systemd/system/prometheus.service
cp /tmp/assets/node_exporter.service /etc/systemd/system/node_exporter.service
cp /tmp/assets/postgres_exporter.service /etc/systemd/system/postgres_exporter.service

# Reload systemd to recognize new services
systemctl daemon-reload
