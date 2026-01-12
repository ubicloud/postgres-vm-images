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

echo "=== Packages setup complete ==="
