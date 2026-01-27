#!/bin/bash
set -uexo pipefail

# Usage: ./build.sh [size_gb]
# Example: ./build.sh 8

TARGET_SIZE_GB="${1:-8}"

# Detect architecture
HOST_ARCH=$(uname -m)
case $HOST_ARCH in
  x86_64)
    UBUNTU_ARCH="amd64"
    IMAGE_ARCH="x64"
    ;;
  aarch64)
    UBUNTU_ARCH="arm64"
    IMAGE_ARCH="arm64"
    ;;
  *)
    echo "Error: Unsupported architecture: $HOST_ARCH"
    exit 1
    ;;
esac

echo "=== Detected architecture: $HOST_ARCH (Ubuntu: $UBUNTU_ARCH, Image: $IMAGE_ARCH) ==="
echo "=== Building PostgreSQL image (${TARGET_SIZE_GB}GB) ==="

# Install dependencies
apt update
apt -y upgrade
apt install -y qemu-utils kpartx parted

# Install guestfs-tools for virt-resize (used only for initial image resizing)
apt install -y guestfs-tools
chmod 0644 /boot/vmlinuz*

# Download Ubuntu cloud image for detected architecture
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-${UBUNTU_ARCH}.img -O cloud.img

# Resize image and expand partition using virt-resize
# This is fast as it just copies/expands data without booting a VM
qemu-img create -f qcow2 resized.img ${TARGET_SIZE_GB}G
virt-resize --expand /dev/sda1 cloud.img resized.img
rm cloud.img
mv resized.img cloud.img

# =====================================
# === DIRECT MOUNT + CHROOT BUILD ===
# =====================================
# This approach bypasses libguestfs/QEMU for script execution
# Scripts run at native speed using loop device mount + chroot

echo "=== Converting to raw for direct mounting ==="
qemu-img convert -f qcow2 -O raw cloud.img cloud.raw
rm cloud.img

echo "=== Setting up loop device and partitions ==="
LOOP_DEV=$(losetup --find --show cloud.raw)
echo "Loop device: ${LOOP_DEV}"

# Use kpartx to create partition mappings
kpartx -av ${LOOP_DEV}
sleep 2  # Give kernel time to create device nodes

# List available partitions
echo "Available partitions:"
ls -la /dev/mapper/"$(basename "${LOOP_DEV}")"* 2>/dev/null || true

# Find the root partition - it's the largest ext4 partition
# Ubuntu cloud images typically have: p1=BIOS boot (small), p14=EFI, p15=root (ext4)
# Or sometimes: p1=root (ext4)
LOOP_BASE=$(basename ${LOOP_DEV})
ROOT_PART=""

# Try each partition and find one with ext4 filesystem
for part in /dev/mapper/${LOOP_BASE}p*; do
    if [ -b "$part" ]; then
        FS_TYPE=$(blkid -o value -s TYPE "$part" 2>/dev/null || echo "")
        echo "Partition $part: filesystem type = $FS_TYPE"
        if [ "$FS_TYPE" = "ext4" ]; then
            ROOT_PART="$part"
            echo "Found root partition: $ROOT_PART"
            break
        fi
    fi
done

if [ -z "$ROOT_PART" ]; then
    echo "Error: Could not find ext4 root partition"
    exit 1
fi

echo "Root partition: ${ROOT_PART}"

# Create mount point
MOUNT_POINT="/mnt/image"
mkdir -p ${MOUNT_POINT}

echo "=== Mounting root filesystem ==="
mount ${ROOT_PART} ${MOUNT_POINT}

# Set up DNS resolution BEFORE mounting /run (to avoid symlink issues)
# resolv.conf may be a symlink to /run/systemd/resolve/stub-resolv.conf
mkdir -p ${MOUNT_POINT}/run/systemd/resolve
cat /etc/resolv.conf > ${MOUNT_POINT}/etc/resolv.conf || \
    echo "nameserver 8.8.8.8" > ${MOUNT_POINT}/etc/resolv.conf

# Mount necessary filesystems for chroot
mount --bind /dev ${MOUNT_POINT}/dev
mount --bind /dev/pts ${MOUNT_POINT}/dev/pts
mount --bind /proc ${MOUNT_POINT}/proc
mount --bind /sys ${MOUNT_POINT}/sys
# Note: We don't bind /run to avoid conflicts with resolv.conf symlink

# Configure faster mirror for ARM builds
if [ "${UBUNTU_ARCH}" = "arm64" ]; then
    echo "=== Configuring German mirror for ARM packages ==="
    echo "APT source files before update:"
    ls -la ${MOUNT_POINT}/etc/apt/sources.list* ${MOUNT_POINT}/etc/apt/sources.list.d/ 2>/dev/null || true

    # Update all APT source files (sources.list and everything in sources.list.d)
    for src_file in ${MOUNT_POINT}/etc/apt/sources.list ${MOUNT_POINT}/etc/apt/sources.list.d/*; do
        if [ -f "$src_file" ]; then
            echo "Updating: $src_file"
            sed -i 's|ports.ubuntu.com|de.ports.ubuntu.com|g' "$src_file"
        fi
    done

    echo "=== APT sources after mirror update ==="
    cat ${MOUNT_POINT}/etc/apt/sources.list 2>/dev/null || true
    for f in ${MOUNT_POINT}/etc/apt/sources.list.d/*; do
        [ -f "$f" ] && echo "--- $f ---" && cat "$f"
    done
fi

# Copy scripts into the mounted image
echo "=== Copying scripts to image ==="
cp -r common ${MOUNT_POINT}/tmp/

# Write architecture info
cat > ${MOUNT_POINT}/tmp/build_arch.env << EOF
UBUNTU_ARCH=${UBUNTU_ARCH}
IMAGE_ARCH=${IMAGE_ARCH}
EOF

# Make scripts executable
chmod +x ${MOUNT_POINT}/tmp/common/*.sh

echo "=== Running setup scripts in chroot (NATIVE SPEED!) ==="

# Run all setup scripts in chroot - this runs at native speed, no QEMU!
chroot ${MOUNT_POINT} /bin/bash -c "
  set -uexo pipefail
  export DEBIAN_FRONTEND=noninteractive

  echo '=== Running setup_base.sh ==='
  /tmp/common/setup_base.sh

  echo '=== Running setup_packages.sh ==='
  /tmp/common/setup_packages.sh

  echo '=== Running setup_monitoring.sh ==='
  /tmp/common/setup_monitoring.sh

  echo '=== Running setup_cleanup.sh ==='
  /tmp/common/setup_cleanup.sh
"

echo "=== Running final cleanup in chroot ==="
chroot ${MOUNT_POINT} /bin/bash -c "
  set -uexo pipefail
  export DEBIAN_FRONTEND=noninteractive

  # Show disk usage
  df -h

  # Remove SSH host keys (will be regenerated on first boot)
  rm -f /etc/ssh/ssh_host_*

  # Delete root password
  passwd -d root

  # Clean package cache and logs
  apt-get clean
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /var/log/*
  rm -f /root/.bash_history /root/.lesshst
  rm -rf /root/.cache /tmp/* /var/tmp/*

  # Clean cloud-init
  rm -rf /var/lib/cloud
  cloud-init clean --logs || true
"

# Zero-fill free space for better compression
echo "=== Zero-filling free space ==="
dd if=/dev/zero of=${MOUNT_POINT}/zero.fill bs=1M 2>/dev/null || true
rm -f ${MOUNT_POINT}/zero.fill

# Truncate machine-id
truncate -s 0 ${MOUNT_POINT}/etc/machine-id

echo "=== Unmounting filesystems ==="
# Unmount in reverse order
umount ${MOUNT_POINT}/sys || true
umount ${MOUNT_POINT}/proc || true
umount ${MOUNT_POINT}/dev/pts || true
umount ${MOUNT_POINT}/dev || true
umount ${MOUNT_POINT}

echo "=== Cleaning up loop devices ==="
kpartx -dv ${LOOP_DEV}
losetup -d ${LOOP_DEV}

# Rename to final output
mv cloud.raw postgres-${IMAGE_ARCH}-image.raw

echo "Final image size:"
ls -lh postgres-${IMAGE_ARCH}-image.raw
du -h postgres-${IMAGE_ARCH}-image.raw

echo "=== Build complete: postgres-${IMAGE_ARCH}-image.raw ==="
