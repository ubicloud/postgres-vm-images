#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== Configuring PostgreSQL repositories ==="

# Add PostgreSQL repository
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg
sh -c 'echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# Add golang PPA for WAL-G
add-apt-repository -y ppa:longsleep/golang-backports

# Update package lists
apt-get update

echo "=== Installing PostgreSQL ==="

# Install postgresql-common and configure it
apt-get install -y postgresql-common

# Configure PostgreSQL with data checksums and no auto cluster creation
echo "initdb_options = '--data-checksums'" >> /etc/postgresql-common/createcluster.conf
echo "create_main_cluster = 'off'" >> /etc/postgresql-common/createcluster.conf
mkdir -p /etc/postgresql-common/createcluster.d
echo "include_dir = '/etc/postgresql-common/createcluster.d'" >> /etc/postgresql-common/createcluster.conf

# Copy package lists to reference location
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
xargs -a /tmp/postgresql-packages.txt apt-get -y install --download-only

echo "=== Setting up users and groups ==="

# Create users
adduser --disabled-password --gecos '' prometheus
adduser --disabled-password --gecos '' ubi_monitoring

# Create cert_readers group and add users to it
groupadd cert_readers
usermod --append --groups cert_readers postgres
usermod --append --groups cert_readers prometheus

echo "=== Base setup complete ==="
