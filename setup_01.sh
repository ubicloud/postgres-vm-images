#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== Configuring PostgreSQL repositories and settings ==="

# Create the PostgreSQL APT repository configuration for future use
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg || true

# Add golang backports PPA for future use
add-apt-repository -y ppa:longsleep/golang-backports || true

# Copy package lists to reference location
mkdir -p /usr/local/share/postgresql/packages
cp /tmp/assets/16.txt /tmp/assets/17.txt /tmp/assets/18.txt /tmp/assets/common.txt /usr/local/share/postgresql/packages/
chown -R root:root /usr/local/share/postgresql/packages
chmod 755 /usr/local/share/postgresql/packages
chmod 644 /usr/local/share/postgresql/packages/*.txt

echo "=== Installing PostgreSQL packages from cache ==="

# Install packages from our downloaded cache
cd /tmp/downloads/packages

# Install build dependencies first (needed for WAL-G and pguint)
dpkg -i make_*.deb || true
dpkg -i gcc_*.deb g++_*.deb || true
dpkg -i build-essential_*.deb || true
dpkg -i cmake_*.deb || true
dpkg -i git_*.deb || true

# Fix any dependency issues
apt-get install -f -y || true

# Install golang packages for WAL-G
dpkg -i golang-*.deb || true
apt-get install -f -y || true

# Install postgresql-common and configure it
dpkg -i postgresql-common*.deb || true
apt-get install -f -y || true

# Configure PostgreSQL with data checksums and no auto cluster creation
echo "initdb_options = '--data-checksums'" >> /etc/postgresql-common/createcluster.conf
echo "create_main_cluster = 'off'" >> /etc/postgresql-common/createcluster.conf
mkdir -p /etc/postgresql-common/createcluster.d
echo "include_dir = '/etc/postgresql-common/createcluster.d'" >> /etc/postgresql-common/createcluster.conf

# Install all PostgreSQL packages (they won't auto-create clusters due to config above)
# This ensures packages are available and cached for specific version installations
for deb in postgresql-*.deb pgbouncer*.deb; do
    [ -f "$deb" ] && dpkg -i "$deb" || true
done

# Fix any remaining dependency issues
apt-get install -f -y || true

cd /

echo "=== Setting up users and groups ==="

# Create users
adduser --disabled-password --gecos '' prometheus || true
adduser --disabled-password --gecos '' ubi_monitoring || true

# Create cert_readers group and add users to it
groupadd cert_readers || true
usermod --append --groups cert_readers postgres || true
usermod --append --groups cert_readers prometheus || true

echo "=== Copying source code for building ==="

# Copy WAL-G and pguint source for building
mkdir -p /usr/local/src
cp -r /tmp/downloads/sources/wal-g /usr/local/src/ 2>/dev/null || true
cp -r /tmp/downloads/sources/pguint /usr/local/src/ 2>/dev/null || true

echo "=== Setup 01 complete ==="
echo "PostgreSQL packages installed, users configured, WAL-G and pguint source ready for build"
