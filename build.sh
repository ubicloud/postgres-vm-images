#!/bin/bash
set -uexo pipefail

# Target final image size in GB (default 8GB)
TARGET_SIZE_GB="${1:-8}"

# Install dependencies
apt update
apt -y upgrade
apt install -y guestfs-tools

# Configure permissions for libguestfs
chmod 0644 /boot/vmlinuz*
chmod 0666 /dev/kvm

# Download Ubuntu cloud image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O cloud.img

# Resize to target size
qemu-img resize cloud.img ${TARGET_SIZE_GB}G

# Copy setup scripts and assets
virt-customize -a cloud.img \
  --copy-in setup_01.sh:/tmp/ \
  --copy-in setup_02.sh:/tmp/ \
  --copy-in setup_03.sh:/tmp/ \
  --copy-in assets:/tmp/

# Expand partition and filesystem
virt-customize -a cloud.img --run-command "growpart /dev/sda 1"
virt-customize -a cloud.img --run-command "resize2fs /dev/sda1"

# Make scripts executable and run them
virt-customize -a cloud.img --run-command "chmod +x /tmp/setup_01.sh /tmp/setup_02.sh /tmp/setup_03.sh"
virt-customize -a cloud.img --run-command "/tmp/setup_01.sh"
virt-customize -a cloud.img --run-command "/tmp/setup_02.sh"
virt-customize -a cloud.img --run-command "/tmp/setup_03.sh"

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
qemu-img convert -p -f qcow2 -O raw cloud.img postgres-vm-image.raw

echo "Final image size:"
ls -lh postgres-vm-image.raw
du -h postgres-vm-image.raw
