#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

# Update OpenSSH
apt-get update -qq
apt -qq -y satisfy 'openssh-server (>= 1:8.9p1-3ubuntu0.10)'

# Add PostgreSQL repository
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

# Update package lists
apt-get update

# Install postgresql-common first with custom configuration
apt-get -y install postgresql-common

# Configure createcluster settings
echo "initdb_options = '--data-checksums'" | tee -a /etc/postgresql-common/createcluster.conf
echo "create_main_cluster = 'off'" | tee -a /etc/postgresql-common/createcluster.conf
mkdir -p /etc/postgresql-common/createcluster.d
echo "include_dir = '/etc/postgresql-common/createcluster.d'" | tee -a /etc/postgresql-common/createcluster.conf

# Create package files directory
mkdir -p /usr/local/share/postgresql/packages
cp /tmp/assets/*.txt /usr/local/share/postgresql/packages/

# Combine all package files
cat /usr/local/share/postgresql/packages/16.txt > /tmp/postgresql-packages.txt
cat /usr/local/share/postgresql/packages/17.txt >> /tmp/postgresql-packages.txt
cat /usr/local/share/postgresql/packages/18.txt >> /tmp/postgresql-packages.txt
cat /usr/local/share/postgresql/packages/common.txt >> /tmp/postgresql-packages.txt

# Download PostgreSQL packages (don't install yet - just cache them)
xargs -a /tmp/postgresql-packages.txt apt-get -y install --download-only

# Install WAL-G dependencies and build it
add-apt-repository -y ppa:longsleep/golang-backports
apt-get update
apt-get -y install golang-go cmake git

# Build WAL-G
mkdir -p /var/wal-g
cd /var/wal-g
git init
git remote remove origin || true
git remote add origin https://github.com/wal-g/wal-g.git
git fetch origin --depth 1 cf1ce0f5b69048e31d740b508a79d8294707e339
git reset --hard FETCH_HEAD
make deps
make pg_build
GOBIN=/usr/bin make pg_install

# Set up users and groups
adduser --disabled-password --gecos '' prometheus || true
adduser --disabled-password --gecos '' ubi_monitoring || true
groupadd cert_readers || true
usermod --append --groups cert_readers postgres
usermod --append --groups cert_readers prometheus
