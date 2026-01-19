#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

# Read architecture from build_arch.env
source /tmp/build_arch.env

echo "=== [setup_packages.sh] Architecture: ${UBUNTU_ARCH} ==="

echo "=== [setup_packages.sh] Installing build dependencies ==="

# Install build tools (cmake for pguint, golang for WAL-G and daemon-client)
echo "[setup_packages.sh] Installing golang-go and cmake..."
apt-get install -y golang-go cmake

# Install Python and PostgreSQL development packages for all versions
echo "[setup_packages.sh] Installing python3, pip, and postgresql-server-dev packages..."
apt-get install -y python3 python3-pip postgresql-server-dev-16 postgresql-server-dev-17 postgresql-server-dev-18

# Create symlink for python if needed (may already exist)
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true

echo "=== [setup_packages.sh] Building and installing WAL-G ==="

# Clone and build WAL-G from source
# Now running in chroot at native speed (not QEMU emulation), this should be fast
echo "[setup_packages.sh] Cloning WAL-G repository..."
mkdir -p /tmp/wal-g
cd /tmp/wal-g
git init
git remote add origin https://github.com/wal-g/wal-g.git
git fetch origin --depth 1 6ea13b90a3198bd5c8f8ac2ae323f28e33cf9f06
git reset --hard FETCH_HEAD

echo "[setup_packages.sh] Running make deps (downloading Go dependencies)..."
make deps

echo "[setup_packages.sh] Running make pg_build (compiling WAL-G for ${UBUNTU_ARCH})..."
make pg_build

echo "[setup_packages.sh] Installing WAL-G..."
GOBIN=/usr/bin make pg_install

echo "[setup_packages.sh] WAL-G installed: $(wal-g --version || echo 'version check failed')"

echo "[setup_packages.sh] Building WAL-G daemon client..."
make build_client
cp bin/walg-daemon-client /usr/bin/walg-daemon-client
chmod +x /usr/bin/walg-daemon-client

# Clean up WAL-G source
cd /tmp
rm -rf /tmp/wal-g

echo "=== [setup_packages.sh] Building and installing pguint extension ==="

# Clone and build pguint for each PostgreSQL version
echo "[setup_packages.sh] Cloning pguint repository..."
cd /tmp
git clone https://github.com/petere/pguint.git
cd pguint

# Build for PG 16
echo "[setup_packages.sh] Building pguint for PostgreSQL 16..."
make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config
make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config install
make clean

# Build for PG 17
echo "[setup_packages.sh] Building pguint for PostgreSQL 17..."
make PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config
make PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config install
make clean

# Build for PG 18
echo "[setup_packages.sh] Building pguint for PostgreSQL 18..."
make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config
make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config install

# Clean up
cd /tmp
rm -rf pguint

echo "=== [setup_packages.sh] Complete ==="
