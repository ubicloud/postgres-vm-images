#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive
export HOME=/root

# Read architecture from build_arch.env
source /tmp/build_arch.env

echo "=== [setup_packages.sh] Architecture: ${UBUNTU_ARCH} ==="

echo "=== [setup_packages.sh] Installing build dependencies ==="

# Build tools: cmake for pguint; cmake + C toolchain + perl for wal-rus's
# aws-lc-rs dependency; Rust toolchain compiles wal-rus
echo "[setup_packages.sh] Installing cmake, build-essential, perl..."
apt-get install -y cmake build-essential perl

# Isolated toolchain dirs so cleanup is a single rm -rf, not ~/.cargo et al
export RUSTUP_HOME=/opt/rustup
export CARGO_HOME=/opt/cargo
echo "[setup_packages.sh] Installing Rust toolchain..."
curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal --default-toolchain stable
export PATH=$CARGO_HOME/bin:$PATH
rustc --version

# Install Python and PostgreSQL development packages for all versions
echo "[setup_packages.sh] Installing python3, pip, and postgresql-server-dev packages..."
apt-get install -y python3 python3-pip unzip postgresql-server-dev-16 postgresql-server-dev-17 postgresql-server-dev-18

# Create symlink for python if needed (may already exist)
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true

echo "=== [setup_packages.sh] Building and installing wal-rus (drop-in wal-g) ==="

# wal-rus port of wal-g. Installs as /usr/bin/wal-g & /usr/bin/walg-daemon-client
# (one binary, daemon-client name dispatched via argv[0])
WALRUS_REF=d2c464166a50ef0b325741dcc4c269edecdc0a66
echo "[setup_packages.sh] Cloning wal-rus repository..."
mkdir -p /tmp/wal-rus
cd /tmp/wal-rus
git init
git remote add origin https://github.com/ClickHouse/wal-rus.git
git fetch origin --depth 1 ${WALRUS_REF}
git reset --hard FETCH_HEAD

echo "[setup_packages.sh] Building wal-rus (cargo build --release for ${UBUNTU_ARCH})..."
cargo build --release --locked --bin walrus

echo "[setup_packages.sh] Installing wal-rus as wal-g + walg-daemon-client..."
install -m 0755 target/release/walrus /usr/bin/wal-g
ln -sf wal-g /usr/bin/walg-daemon-client

echo "[setup_packages.sh] wal-g installed: $(wal-g --version || echo 'version check failed')"

# Clean up wal-rus source, target dir, registry cache, and Rust toolchain
cd /tmp
rm -rf /tmp/wal-rus /opt/rustup /opt/cargo

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
git fetch origin --depth 1 ce0d160b8503f98c179646e38cd24b9351ec8c0a
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
