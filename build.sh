#!/bin/bash
set -uexo pipefail

# Target final image size in GB (default 8GB to match postgres-images)
TARGET_SIZE_GB="${1:-8}"

# Configure libguestfs to work in GitHub Actions environment
# Use direct backend to avoid passt networking issues
export LIBGUESTFS_BACKEND=direct

apt-get update
apt-get install -y guestfs-tools
chmod 0644 /boot/vmlinuz*
chmod 0666 /dev/kvm || true

wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O cloud.img

# Resize by adding space (using + is required to avoid passt networking issues)
# Add slightly less than target since cloud image is ~660MB
RESIZE_AMOUNT=$((TARGET_SIZE_GB - 1))
qemu-img resize cloud.img +${RESIZE_AMOUNT}G

# Copy small files with virt-customize
virt-customize --no-network -a cloud.img \
  --copy-in setup_01.sh:/tmp/ \
  --copy-in setup_02.sh:/tmp/ \
  --copy-in setup_03.sh:/tmp/ \
  --copy-in assets:/tmp/

# Copy large downloads directory separately with virt-copy-in
# This avoids passt networking initialization issues with large data
virt-copy-in -a cloud.img downloads /tmp/

virt-customize --no-network -a cloud.img --run-command "
  growpart /dev/sda 1;
  resize2fs /dev/sda1;
  chmod +x /tmp/setup_01.sh;
  chmod +x /tmp/setup_02.sh;
  chmod +x /tmp/setup_03.sh;
"

virt-customize --no-network -a cloud.img --run-command "/tmp/setup_01.sh"

virt-customize --no-network -a cloud.img --run-command "/tmp/setup_02.sh"

virt-customize --no-network -a cloud.img --run-command "/tmp/setup_03.sh"

virt-customize --no-network -a cloud.img --run-command "df -h > /tmp/df.txt"
virt-cat -a cloud.img /tmp/df.txt

# =====================================
# ============== CLEAN UP =============
# =====================================

# Remove all existing ssh host keys
virt-customize --no-network -a cloud.img --run-command "rm -f /etc/ssh/ssh_host_*"

# Delete the root password
virt-customize --no-network -a cloud.img --run-command "passwd -d root"

# Final cleanup
virt-customize --no-network -a cloud.img --run-command "
  apt-get clean;
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /var/log/*;
  rm -f /root/.bash_history /root/.lesshst /root/.cache;
  rm -rf /tmp/* /var/tmp/*;
  rm -f /var/lib/dbus/machine-id;
  rm -rf /var/lib/cloud;
  cloud-init clean --logs --machine-id;
  truncate -s 0 /etc/machine-id;
  sync;
"

# Compact and convert to raw format
echo "Compacting and converting to raw format..."
virt-sparsify --convert raw cloud.img postgres-vm-image.raw

echo "Final image size:"
ls -lh postgres-vm-image.raw
