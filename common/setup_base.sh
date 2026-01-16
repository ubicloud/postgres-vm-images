#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== [setup_base.sh] Updating OpenSSH ==="

# Update OpenSSH to address security vulnerabilities
apt-get update -qq
apt-get -qq -y satisfy 'openssh-server (>= 1:8.9p1-3ubuntu0.10)'

echo "=== [setup_base.sh] Updating kernel ==="

# Update to kernel 6.8.0-90-generic (Ubuntu 22.04's latest HWE kernel)
apt-get install -y linux-image-6.8.0-90-generic linux-headers-6.8.0-90-generic linux-tools-6.8.0-90-generic

echo "=== [setup_base.sh] Configuring PostgreSQL repositories ==="

# Add PostgreSQL repository
echo "[setup_base.sh] Downloading PostgreSQL GPG key..."
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg
sh -c 'echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# Add golang PPA for WAL-G (--no-update to avoid apt-get update inside add-apt-repository)
echo "[setup_base.sh] Adding golang PPA..."
add-apt-repository -y --no-update ppa:longsleep/golang-backports

# Update package lists
echo "[setup_base.sh] Running apt-get update..."
apt-get update

echo "=== [setup_base.sh] Installing PostgreSQL ==="

# Install postgresql-common and configure it
echo "[setup_base.sh] Installing postgresql-common..."
apt-get install -y postgresql-common

# Configure PostgreSQL with data checksums and no auto cluster creation
echo "[setup_base.sh] Configuring PostgreSQL createcluster settings..."
echo "initdb_options = '--data-checksums'" >> /etc/postgresql-common/createcluster.conf
echo "create_main_cluster = 'off'" >> /etc/postgresql-common/createcluster.conf
mkdir -p /etc/postgresql-common/createcluster.d
echo "include_dir = '/etc/postgresql-common/createcluster.d'" >> /etc/postgresql-common/createcluster.conf

# Copy package lists to reference location
echo "[setup_base.sh] Copying package lists..."
mkdir -p /usr/local/share/postgresql/packages
cp /tmp/common/assets/packages/*.txt /usr/local/share/postgresql/packages/
chown -R root:root /usr/local/share/postgresql/packages
chmod 755 /usr/local/share/postgresql/packages
chmod 644 /usr/local/share/postgresql/packages/*.txt

# Combine package files for all versions
cat /usr/local/share/postgresql/packages/16.txt \
    /usr/local/share/postgresql/packages/17.txt \
    /usr/local/share/postgresql/packages/18.txt \
    /usr/local/share/postgresql/packages/common.txt > /tmp/postgresql-packages.txt

# Install packages from the combined list (download-only to cache them)
echo "[setup_base.sh] Downloading PostgreSQL packages (download-only)..."
xargs -a /tmp/postgresql-packages.txt apt-get -y install --download-only

echo "=== [setup_base.sh] Setting up users and groups ==="

# Create users
echo "[setup_base.sh] Creating prometheus and ubi_monitoring users..."
adduser --disabled-password --gecos '' prometheus
adduser --disabled-password --gecos '' ubi_monitoring

# Create cert_readers group and add users to it
echo "[setup_base.sh] Creating cert_readers group..."
groupadd cert_readers
usermod --append --groups cert_readers postgres
usermod --append --groups cert_readers prometheus

echo "=== [setup_base.sh] Complete ==="
