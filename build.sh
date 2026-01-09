#!/bin/bash
set -uexo pipefail

IMAGE_RESIZE_GB="${1:-20}"

apt-get update
apt-get install -y guestfs-tools
chmod 0644 /boot/vmlinuz*
chmod 0666 /dev/kvm || true

wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O cloud.img
qemu-img resize cloud.img +${IMAGE_RESIZE_GB}G

virt-customize -a cloud.img \
  --copy-in setup_01.sh:/tmp/ \
  --copy-in setup_02.sh:/tmp/ \
  --copy-in setup_03.sh:/tmp/ \
  --copy-in assets:/tmp/ \
  --copy-in downloads:/tmp/

virt-customize -a cloud.img --run-command "
  growpart /dev/sda 1;
  resize2fs /dev/sda1;
  chmod +x /tmp/setup_01.sh;
  chmod +x /tmp/setup_02.sh;
  chmod +x /tmp/setup_03.sh;
"

virt-customize -a cloud.img --run-command "/tmp/setup_01.sh"

virt-customize -a cloud.img --run-command "/tmp/setup_02.sh"

virt-customize -a cloud.img --run-command "/tmp/setup_03.sh"

virt-customize -a cloud.img --run-command "df -h > /tmp/df.txt"
virt-cat -a cloud.img /tmp/df.txt

# =====================================
# ============== CLEAN UP =============
# =====================================

# Remove all existing ssh host keys
virt-customize -a cloud.img --run-command "rm -f /etc/ssh/ssh_host_*"

# Delete the root password
virt-customize -a cloud.img --run-command "passwd -d root"

# Final cleanup
virt-customize -a cloud.img --run-command "
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

qemu-img convert -p -f qcow2 -O raw cloud.img postgres-vm-image.raw
