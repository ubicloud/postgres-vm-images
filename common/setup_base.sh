#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

# Read architecture and release info from build.sh
source /tmp/build_arch.env

echo "=== [setup_base.sh] Target release: ${UBUNTU_CODENAME} (${UBUNTU_RELEASE}) ==="

apt-get update -qq

if [ "${UBUNTU_RELEASE}" -ge 2510 ]; then
    echo "=== [setup_base.sh] Pinning GNU coreutils and sudo ==="
    # 25.10+ default to uutils coreutils and sudo-rs. The control plane
    # drives postgres almost entirely through sudo and coreutils
    # (install/chown/truncate/dd against the data directory), and uutils
    # is not 100% GNU-compatible. Pin the GNU implementations; both stay
    # supported in the archive. /usr/bin/sudo is an update-alternatives
    # group: sudo-rs at priority 50 (default), classic sudo.ws at 40.
    # coreutils-from-gnu and coreutils-from-uutils both Conflict the virtual
    # coreutils-from, and the APT 3.0 solver refuses to swap the installed
    # uutils build on its own; mark it for removal (trailing -) explicitly.
    # The uutils build is Essential (it is the coreutils provider), so the
    # swap also needs --allow-remove-essential; the GNU provider replaces it
    # in the same transaction, so the coreutils functionality is preserved.
    apt-get install -y --allow-remove-essential coreutils-from-gnu coreutils-from-uutils- sudo
    update-alternatives --set sudo /usr/bin/sudo.ws
    [[ $(install --version) == *"GNU coreutils"* ]] || { echo "ERROR: GNU coreutils is not the active coreutils"; exit 1; }
    [[ $(sudo --version) == "Sudo version 1."* ]] || { echo "ERROR: classic sudo is not the active sudo"; exit 1; }
fi

echo "=== [setup_base.sh] Generating en_US.UTF-8 locale ==="

# The resolute cloud image ships only C, C.utf8, and POSIX. A PostgreSQL data
# directory created with an en_US.UTF-8 (libc) collation fails to start if that
# locale is absent — an outage, not a corruption risk — so generate it and
# assert the expected set is present before the image ships.
apt-get install -y locales
locale-gen en_US.UTF-8
for loc in C C.utf8 POSIX en_US.utf8; do
    locale -a | grep -qixF "$loc" || { echo "ERROR: expected locale '$loc' missing after locale-gen"; exit 1; }
done

echo "=== [setup_base.sh] Updating kernel ==="

# Ubuntu 26.04 (kernel 7.x) builds the initramfs with dracut, whose default
# hostonly mode bakes the build host's transient loop/kpartx nodes
# (/dev/mapper/loopNpM) into the image. Those nodes do not exist in a real
# guest, so it drops to the dracut emergency shell unable to find its root.
# Force a generic initramfs before the kernel install triggers the first
# dracut run. Inert on releases that use initramfs-tools (e.g. jammy).
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/00-generic.conf <<'EOF'
hostonly="no"
hostonly_cmdline="no"
EOF

# The cloud image ships the GA virtual kernel; install the latest HWE
# generic kernel for this release (on a freshly released LTS the HWE meta
# still points at the GA kernel). Read the ABI off the meta instead of
# installing it: linux-image-generic-hwe-* depends on linux-firmware,
# 1.1GB of hardware blobs a VM never loads.
UBUNTU_VERSION_ID="${UBUNTU_RELEASE:0:2}.${UBUNTU_RELEASE:2:2}"
KERNEL_ABI=$(apt-cache depends "linux-image-generic-hwe-${UBUNTU_VERSION_ID}" | sed -n 's/.*Depends: linux-image-\([0-9].*-generic\)$/\1/p')

# linux-image pulls in linux-modules. Older releases (jammy) split the
# less-common drivers into a separate linux-modules-extra package; 26.04
# folds them back into linux-modules, so no modules-extra package exists.
# Install it only when the archive still ships it for this ABI.
KERNEL_PKGS=("linux-image-$KERNEL_ABI" "linux-headers-$KERNEL_ABI" "linux-tools-$KERNEL_ABI")
if apt-cache show "linux-modules-extra-$KERNEL_ABI" 2>/dev/null | grep -q "^Package:"; then
    KERNEL_PKGS+=("linux-modules-extra-$KERNEL_ABI")
fi
apt-get install -y "${KERNEL_PKGS[@]}"

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

# ubuntu-server no longer depends on rsyslog (since jammy), purge won't cascade
apt-get purge -y rsyslog

mkdir -p /etc/systemd/journald.conf.d
cat <<'EOF' > /etc/systemd/journald.conf.d/50-persistent.conf
[Journal]
Storage=persistent
SystemMaxUse=4G
Compress=yes
ForwardToSyslog=no
EOF

# Install dependency libraries required by PostgreSQL extensions
# These are installed now so dpkg can install extensions at runtime without apt-get update
# Library package names carry sonames (and the noble-era t64 suffix), so
# they differ per release.
echo "[setup_base.sh] Installing PostgreSQL extension dependencies..."
case "${UBUNTU_RELEASE}" in
    2604)
        EXTENSION_LIBS=(libevent-2.1-7t64 libgdal38 libgeos-c1t64 libproj25 libsfcgal2)
        ;;
    2204)
        EXTENSION_LIBS=(libevent-2.1-7 libgdal30 libgeos-c1v5 libproj22 libsfcgal1)
        ;;
    *)
        echo "ERROR: no extension library list for Ubuntu release ${UBUNTU_RELEASE}"
        exit 1
        ;;
esac
apt-get install -y \
    "${EXTENSION_LIBS[@]}" \
    libc-ares2 \
    libh3-1 \
    libprotobuf-c1 \
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
# The ruleset is validated in setup_monitoring.sh, after the otelcol-contrib
# user it references exists (created by the otel collector package).
cp /tmp/common/assets/imds-protection.service /etc/systemd/system/imds-protection.service
systemctl enable imds-protection.service

echo "=== [setup_base.sh] Complete ==="
