#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== [setup_base.sh] Updating OpenSSH ==="

# Update OpenSSH to address security vulnerabilities
apt-get update -qq
apt-get -qq -y satisfy 'openssh-server (>= 1:8.9p1-3ubuntu0.10)'

echo "=== [setup_base.sh] Updating kernel ==="

# Update to kernel 6.8.0-90-generic (Ubuntu 22.04's latest HWE kernel)
apt-get install -y linux-image-6.8.0-90-generic linux-headers-6.8.0-90-generic linux-tools-6.8.0-90-generic linux-modules-extra-6.8.0-90-generic

echo "=== [setup_base.sh] Installing ruby-bundler ==="
apt-get install -y ruby-bundler

echo "=== [setup_base.sh] Configuring PostgreSQL repositories ==="

# Add PostgreSQL repository
echo "[setup_base.sh] Downloading PostgreSQL GPG key..."
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg
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

echo "=== [setup_base.sh] Pinning TZ=UTC ==="
# TZ=UTC parses as a POSIX zone, so glibc skips stat()/read() of /etc/localtime on every localtime() call.
# Also makes initdb default timezone/log_timezone to UTC.
# DefaultEnvironment covers all systemd services (postgres + monitoring),
# /etc/environment covers login shells and control-plane initdb.
# https://blog.packagecloud.io/set-environment-variable-save-thousands-of-system-calls
mkdir -p /etc/systemd/system.conf.d
cat <<'EOF' > /etc/systemd/system.conf.d/tz.conf
[Manager]
DefaultEnvironment=TZ=UTC
EOF
echo 'TZ=UTC' >> /etc/environment

echo "=== [setup_base.sh] Replacing rsyslog with persistent journald ==="

# jammy ubuntu-server no longer depends on rsyslog, purge won't cascade
apt-get purge -y rsyslog

mkdir -p /etc/systemd/journald.conf.d
cat <<'EOF' > /etc/systemd/journald.conf.d/50-persistent.conf
[Journal]
Storage=persistent
SystemMaxUse=4G
Compress=yes
ForwardToSyslog=no
EOF

# Install dependency libraries required by PostgreSQL extensions and by the
# pgcopydb migrator (libgc1). Installed now so runtime dpkg of the baked .debs
# resolves offline, with no apt-get update / network.
echo "[setup_base.sh] Installing PostgreSQL extension dependencies..."
apt-get install -y \
    libc-ares2 \
    libevent-2.1-7 \
    libgc1 \
    libh3-1 \
    libgdal30 \
    libgeos-c1v5 \
    libproj22 \
    libprotobuf-c1 \
    libsfcgal1 \
    libsybdb5 \
    liburing2 \
    default-libmysqlclient-dev \
    python3-psycopg2

# Copy package lists to reference location
echo "[setup_base.sh] Copying package lists..."
mkdir -p /usr/local/share/postgresql/packages
cp /tmp/common/assets/packages/*.txt /usr/local/share/postgresql/packages/
chown -R root:root /usr/local/share/postgresql/packages
chmod 755 /usr/local/share/postgresql/packages
chmod 644 /usr/local/share/postgresql/packages/*.txt

# Install helper script for runtime package installation
echo "[setup_base.sh] Installing package installation helper script..."
cp /tmp/common/assets/scripts/install-postgresql-packages.sh /usr/local/bin/install-postgresql-packages
chmod 755 /usr/local/bin/install-postgresql-packages

# Download .deb packages to version-specific directories for dpkg installation at runtime
echo "[setup_base.sh] Downloading PostgreSQL packages as .deb files..."
PACKAGE_CACHE="/var/cache/postgresql-packages"

for version in 16 17 18; do
    echo "[setup_base.sh] Downloading packages for PostgreSQL $version..."
    mkdir -p "$PACKAGE_CACHE/$version"
    pushd "$PACKAGE_CACHE/$version" > /dev/null
    xargs -a /usr/local/share/postgresql/packages/$version.txt apt-get download
    popd > /dev/null
done

echo "[setup_base.sh] Downloading common packages..."
mkdir -p "$PACKAGE_CACHE/common"
pushd "$PACKAGE_CACHE/common" > /dev/null
xargs -a /usr/local/share/postgresql/packages/common.txt apt-get download
popd > /dev/null

# apt-get download can exit 0 without staging a file, so assert the baked client
# majors landed. 6fd02f6 baked these into the cache precisely so the migrator no
# longer relies on the incidental server-dev build dep; a silent download loss
# would revert to that implicit state, and the runtime psql check would still
# pass off the build-dep binaries -- hiding the regression until a future image
# slimming purges those deps.
for major in 16 17 18; do
    if ! ls "$PACKAGE_CACHE"/common/postgresql-client-${major}_*.deb > /dev/null 2>&1; then
        echo "[setup_base.sh] ERROR: postgresql-client-${major} .deb missing from cache after download" >&2
        exit 1
    fi
done

# Download pgcopydb pinned to the 0.18 upstream minor for the managed-Postgres
# migrator (SPEC 9.1). Lands in the common cache so install-postgresql-packages
# stages it for every target major alongside the client packages. Pin the minor
# and let the PGDG packaging revision float; fail the build if 0.18 is ever gone.
PGCOPYDB_VERSION="0.18"
echo "[setup_base.sh] Downloading pgcopydb (pinned to ${PGCOPYDB_VERSION})..."
PGCOPYDB_VERSION_FULL=$(apt-cache madison pgcopydb | awk -v v="$PGCOPYDB_VERSION" '$3 ~ ("^" v "[-.]") {print $3; exit}')
if [ -z "$PGCOPYDB_VERSION_FULL" ]; then
    echo "[setup_base.sh] ERROR: pgcopydb ${PGCOPYDB_VERSION} not available in PGDG" >&2
    exit 1
fi
pushd "$PACKAGE_CACHE/common" > /dev/null
apt-get download "pgcopydb=${PGCOPYDB_VERSION_FULL}"
popd > /dev/null

# apt-get download can exit 0 without staging a file, so assert the .deb landed.
# Otherwise a green build ships an image whose runtime install silently omits
# pgcopydb, leaving every migration ineligible with no signal until exec time.
if ! ls "$PACKAGE_CACHE"/common/pgcopydb_*.deb > /dev/null 2>&1; then
    echo "[setup_base.sh] ERROR: pgcopydb .deb missing from cache after download" >&2
    exit 1
fi

# Download VectorChord extension packages from GitHub releases
# Not available in PostgreSQL APT repo, so downloaded separately
echo "[setup_base.sh] Downloading VectorChord extension packages..."
VCHORD_VERSION="1.1.1"
VCHORD_VERSION_FULL="1.1.1-1"
PG_TOKENIZER_VERSION="0.1.1"
PG_TOKENIZER_VERSION_FULL="0.1.1-1"
VCHORD_BM25_VERSION="0.3.0"
VCHORD_BM25_VERSION_FULL="0.3.0-1"
UBUNTU_ARCH=$(dpkg --print-architecture)
for version in 16 17 18; do
    echo "[setup_base.sh] Downloading VectorChord for PostgreSQL $version ($UBUNTU_ARCH)..."
    curl -L -o "$PACKAGE_CACHE/$version/postgresql-${version}-vchord.deb" \
        "https://github.com/tensorchord/VectorChord/releases/download/${VCHORD_VERSION}/postgresql-${version}-vchord_${VCHORD_VERSION_FULL}_${UBUNTU_ARCH}.deb"

    echo "[setup_base.sh] Downloading pg_tokenizer for PostgreSQL $version ($UBUNTU_ARCH)..."
    curl -L -o "$PACKAGE_CACHE/$version/postgresql-${version}-pg-tokenizer.deb" \
        "https://github.com/tensorchord/pg_tokenizer.rs/releases/download/${PG_TOKENIZER_VERSION}/postgresql-${version}-pg-tokenizer_${PG_TOKENIZER_VERSION_FULL}_${UBUNTU_ARCH}.deb"

    echo "[setup_base.sh] Downloading VectorChord-bm25 for PostgreSQL $version ($UBUNTU_ARCH)..."
    curl -L -o "$PACKAGE_CACHE/$version/postgresql-${version}-vchord-bm25.deb" \
        "https://github.com/tensorchord/VectorChord-bm25/releases/download/${VCHORD_BM25_VERSION}/postgresql-${version}-vchord-bm25_${VCHORD_BM25_VERSION_FULL}_${UBUNTU_ARCH}.deb"
done

# Capability reporting is owned by the rhizome probe (bin/migration-capabilities,
# PostgresMigrationCapabilities), which runs pgcopydb/pg_restore --version live on
# the VM. No image-side JSON descriptor is baked here: a second, statically-baked
# mechanism would only drift from what runtime dpkg actually installs.

echo "[setup_base.sh] Package cache contents:"
ls -la "$PACKAGE_CACHE"/*

echo "=== [setup_base.sh] Reserving inbound service ports (50001-50032) ==="

cat > /etc/sysctl.d/91-pgbouncer-per-instance-reserved-ports.conf <<'EOF'
# Reserve inbound pgbouncer ports from ephemeral allocation, so outbound connections can't grab one
# Allocating 4x current used for future use
# This sysctl is a single scalar: writing replaces the whole list, never appends.
# Keep this file the sole owner; add future ports to the line below, not a new drop-in.
net.ipv4.ip_local_reserved_ports = 50001-50032
EOF

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

echo "[setup_base.sh] Restricting su to sudo group..."
echo -e '\nauth required pam_wheel.so group=sudo\n' | tee -a /etc/pam.d/su

echo "=== [setup_base.sh] Setting up IMDS protection ==="

apt-get install -y nftables
cp /tmp/common/assets/imds-protection.nftables.conf /etc/nftables.conf
cp /tmp/common/assets/imds-protection.service /etc/systemd/system/imds-protection.service
systemctl enable imds-protection.service

echo "=== [setup_base.sh] Complete ==="
