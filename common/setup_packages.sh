#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive
export HOME=/root
export GOPATH=/root/go

# Read architecture from build_arch.env
source /tmp/build_arch.env

echo "=== [setup_packages.sh] Architecture: ${UBUNTU_ARCH} ==="

echo "=== [setup_packages.sh] Installing build dependencies ==="

# Install build tools (cmake for pguint, golang for WAL-G and daemon-client)
echo "[setup_packages.sh] Installing golang-go and cmake..."
apt-get install -y golang-go cmake

# Install Python and PostgreSQL development packages for all versions
echo "[setup_packages.sh] Installing python3, pip, and postgresql-server-dev packages..."
apt-get install -y python3 python3-pip unzip postgresql-server-dev-16 postgresql-server-dev-17 postgresql-server-dev-18

# Create symlink for python if needed (may already exist)
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true

echo "=== [setup_packages.sh] Building and installing WAL-G ==="

# Clone and build WAL-G from source
# Now running in chroot at native speed (not QEMU emulation), this should be fast
echo "[setup_packages.sh] Cloning WAL-G repository..."
mkdir -p /tmp/wal-g
cd /tmp/wal-g
export GOEXPERIMENT=jsonv2
git init
git remote add origin https://github.com/wal-g/wal-g.git
git fetch origin --depth 1 e4843b849ca05a27655794888341de2662035853
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

echo "=== [setup_packages.sh] Building and installing walg_archive extension ==="

# Clone and build walg_archive for each PostgreSQL version
echo "[setup_packages.sh] Cloning walg_archive repository..."
mkdir -p /tmp/walg_archive
cd /tmp/walg_archive
git init
git remote add origin https://github.com/wal-g/walg_archive.git
git fetch origin --depth 1 ed5674da1a6bbd403ecda971134a67a824b70a2f
git reset --hard FETCH_HEAD

for PG_VERSION in 16 17 18; do
    echo "[setup_packages.sh] Building walg_archive for PostgreSQL ${PG_VERSION}..."
    make USE_PGXS=1 PG_CONFIG=/usr/lib/postgresql/${PG_VERSION}/bin/pg_config
    make USE_PGXS=1 PG_CONFIG=/usr/lib/postgresql/${PG_VERSION}/bin/pg_config install
    make USE_PGXS=1 PG_CONFIG=/usr/lib/postgresql/${PG_VERSION}/bin/pg_config clean
done

cd /tmp
rm -rf walg_archive

# =============================================
# ParadeDB Extensions (x64/amd64 only)
# Download only - installation done at VM runtime
# =============================================
if [ "${UBUNTU_ARCH}" = "amd64" ]; then
    echo "=== [setup_packages.sh] Downloading ParadeDB extensions (x64 only) ==="

    # ParadeDB extension versions
    PG_ANALYTICS_VERSION="0.3.7"  # Only supports PG 16, 17 (archived project)
    PG_SEARCH_VERSION="0.21.2"    # Supports PG 16, 17, 18

    # Create persistent directory for ParadeDB packages
    PARADEDB_PKG_DIR="/var/cache/paradedb"
    mkdir -p ${PARADEDB_PKG_DIR}

    # Download pg_analytics (only PG 16, 17 - no PG 18 support)
    for PG_VERSION in 16 17; do
        echo "[setup_packages.sh] Downloading pg_analytics for PostgreSQL ${PG_VERSION}..."
        curl -L -o ${PARADEDB_PKG_DIR}/postgresql-${PG_VERSION}-pg-analytics.deb \
            "https://github.com/paradedb/pg_analytics/releases/download/v${PG_ANALYTICS_VERSION}/postgresql-${PG_VERSION}-pg-analytics_${PG_ANALYTICS_VERSION}-1PARADEDB-jammy_amd64.deb"
    done

    # Download pg_search (PG 16, 17, 18)
    for PG_VERSION in 16 17 18; do
        echo "[setup_packages.sh] Downloading pg_search for PostgreSQL ${PG_VERSION}..."
        curl -L -o ${PARADEDB_PKG_DIR}/postgresql-${PG_VERSION}-pg-search.deb \
            "https://github.com/paradedb/paradedb/releases/download/v${PG_SEARCH_VERSION}/postgresql-${PG_VERSION}-pg-search_${PG_SEARCH_VERSION}-1PARADEDB-jammy_amd64.deb"
    done

    echo "[setup_packages.sh] ParadeDB packages downloaded to ${PARADEDB_PKG_DIR}:"
    ls -la ${PARADEDB_PKG_DIR}/
else
    echo "[setup_packages.sh] Skipping ParadeDB extensions (arm64 not supported)"
fi

# Timescale pg_textsearch (BM25 ranking). Prebuilt debs exist for
# PG 17 and 18 on amd64 and arm64; PG 16 has no upstream build.
PG_TEXTSEARCH_VERSION="1.3.0"
PG_TEXTSEARCH_TMP="/tmp/pg_textsearch"
mkdir -p ${PG_TEXTSEARCH_TMP}
for PG_VERSION in 17 18; do
    echo "[setup_packages.sh] Installing pg_textsearch for PostgreSQL ${PG_VERSION}..."
    curl -fL -o ${PG_TEXTSEARCH_TMP}/pg${PG_VERSION}.zip \
        "https://github.com/timescale/pg_textsearch/releases/download/v${PG_TEXTSEARCH_VERSION}/pg-textsearch-v${PG_TEXTSEARCH_VERSION}-pg${PG_VERSION}-${UBUNTU_ARCH}.zip"
    unzip -o -d ${PG_TEXTSEARCH_TMP} ${PG_TEXTSEARCH_TMP}/pg${PG_VERSION}.zip
    apt-get install -y ${PG_TEXTSEARCH_TMP}/pg-textsearch-postgresql-${PG_VERSION}_${PG_TEXTSEARCH_VERSION}-1_${UBUNTU_ARCH}.deb
done
rm -rf ${PG_TEXTSEARCH_TMP}

echo "=== [setup_packages.sh] Complete ==="
