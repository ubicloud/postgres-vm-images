#!/bin/bash
set -uexo pipefail

# Usage: ./build.sh <flavor> [size_gb]
# Example: ./build.sh standard 8
# Example: ./build.sh paradedb 8

FLAVOR="${1:-standard}"
TARGET_SIZE_GB="${2:-8}"

# Validate flavor exists
if [ ! -d "flavors/${FLAVOR}" ]; then
    echo "Error: Flavor '${FLAVOR}' not found in flavors/"
    echo "Available flavors:"
    ls -1 flavors/
    exit 1
fi

echo "=== Building ${FLAVOR} PostgreSQL image (${TARGET_SIZE_GB}GB) ==="

# Install dependencies
apt update
apt -y upgrade
apt install -y guestfs-tools

# Configure permissions for libguestfs
chmod 0644 /boot/vmlinuz*

# Download Ubuntu cloud image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O cloud.img

# Resize image and expand partition using virt-resize
qemu-img create -f qcow2 resized.img ${TARGET_SIZE_GB}G
virt-resize --expand /dev/sda1 cloud.img resized.img
mv resized.img cloud.img

# Copy common scripts and assets
virt-customize -a cloud.img \
  --copy-in common:/tmp/

# Copy flavor-specific scripts and assets
virt-customize -a cloud.img \
  --mkdir /tmp/flavors \
  --copy-in flavors/${FLAVOR}:/tmp/flavors/

# Make all scripts executable
virt-customize -a cloud.img --run-command "chmod +x /tmp/common/*.sh /tmp/flavors/${FLAVOR}/*.sh"

# Run common setup scripts
echo "=== Running common setup scripts ==="
virt-customize -a cloud.img --run-command "/tmp/common/setup_base.sh"
virt-customize -a cloud.img --run-command "/tmp/common/setup_packages.sh"
virt-customize -a cloud.img --run-command "/tmp/common/setup_monitoring.sh"

# Run flavor-specific setup
echo "=== Running ${FLAVOR} flavor setup ==="
virt-customize -a cloud.img --run-command "/tmp/flavors/${FLAVOR}/setup.sh"

# Run cleanup (Ubicloud-specific)
echo "=== Running cleanup ==="
virt-customize -a cloud.img --run-command "/tmp/common/setup_cleanup.sh"

# Copy flavor-specific post-installation script if it exists
if [ -f "flavors/${FLAVOR}/assets/post-installation-script" ]; then
    virt-customize -a cloud.img --run-command "mkdir -p /etc/postgresql-partners"
    virt-customize -a cloud.img --copy-in flavors/${FLAVOR}/assets/post-installation-script:/etc/postgresql-partners/
fi

# Show disk usage
virt-customize -a cloud.img --run-command "df -h > /tmp/df.txt"
virt-cat -a cloud.img /tmp/df.txt

# =====================================
# ============== CLEAN UP =============
# =====================================

# Remove SSH host keys (will be regenerated on first boot)
virt-customize -a cloud.img --run-command "rm -f /etc/ssh/ssh_host_*"

# Delete root password
virt-customize -a cloud.img --run-command "passwd -d root"

# Clean package cache and logs
virt-customize -a cloud.img --run-command "
  apt-get clean
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /var/log/*
  rm -f /root/.bash_history /root/.lesshst
  rm -rf /root/.cache
  rm -rf /tmp/* /var/tmp/*
"

# Zero-fill free space for better compression (dd fails when full, which is expected)
virt-customize -a cloud.img --run-command "dd if=/dev/zero of=/zero.fill bs=1M 2>/dev/null; rm -f /zero.fill"

# Clean cloud-init and machine-id
virt-customize -a cloud.img --run-command "rm -rf /var/lib/cloud"
virt-customize -a cloud.img --run-command "cloud-init clean --logs"
virt-customize -a cloud.img --truncate /etc/machine-id

# Convert to raw format
echo "Converting to raw format..."
qemu-img convert -p -f qcow2 -O raw cloud.img postgres-${FLAVOR}-image.raw

echo "Final image size:"
ls -lh postgres-${FLAVOR}-image.raw
du -h postgres-${FLAVOR}-image.raw

echo "=== Build complete: postgres-${FLAVOR}-image.raw ==="
