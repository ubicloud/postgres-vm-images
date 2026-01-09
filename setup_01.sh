#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== Configuring PostgreSQL repositories and settings ==="

# Install postgresql-common from the base repos (it should already be there)
# If not, it will be installed on first boot

# Create the PostgreSQL APT repository configuration
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - || true

# Add golang backports PPA for WAL-G building on first boot
add-apt-repository -y ppa:longsleep/golang-backports || true

# Copy package lists to reference location for documentation
mkdir -p /usr/local/share/postgresql/packages
cp /tmp/assets/*.txt /usr/local/share/postgresql/packages/ || true

# Copy downloaded packages to /var/cache for later installation
mkdir -p /var/cache/postgresql-packages
cp /tmp/downloads/packages/*.deb /var/cache/postgresql-packages/ 2>/dev/null || true

# Copy WAL-G source for building on first boot
mkdir -p /usr/local/src
cp -r /tmp/downloads/sources/wal-g /usr/local/src/ 2>/dev/null || true

echo "=== Setting up users and groups ==="

# Set up users and groups
adduser --disabled-password --gecos '' prometheus || true
adduser --disabled-password --gecos '' ubi_monitoring || true
groupadd cert_readers || true
# Note: postgres user will be created when PostgreSQL is installed

echo "=== Setup 01 complete ==="
echo "PostgreSQL packages and WAL-G source copied to /var/cache/postgresql-packages and /usr/local/src/wal-g"
echo "These can be installed/built on first boot via cloud-init or manually"
