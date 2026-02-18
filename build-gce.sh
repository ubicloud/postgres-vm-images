#!/bin/bash
set -uexo pipefail

# Usage: ./build-gce.sh [size_gb]
# Builds a GCE-compatible PostgreSQL VM image.
# Wraps build.sh and adds:
#   1. GRUB reinstall for BIOS boot (virt-resize can corrupt it)
#   2. Google guest agent for metadata/SSH/startup-script support
#   3. Tar.gz packaging for gcloud compute images create

TARGET_SIZE_GB="${1:-8}"

HOST_ARCH=$(uname -m)
case $HOST_ARCH in
  x86_64)  IMAGE_ARCH="x64" ;;
  aarch64) IMAGE_ARCH="arm64" ;;
  *)       echo "Unsupported architecture: $HOST_ARCH"; exit 1 ;;
esac

# Step 1: Run the standard build
./build.sh "$TARGET_SIZE_GB"

IMAGE_FILE="postgres-${IMAGE_ARCH}-image.raw"
echo "=== GCE post-processing: ${IMAGE_FILE} ==="

# Step 2: Mount image and apply GCE-specific fixes
LOOP_DEV=$(losetup --find --show "${IMAGE_FILE}")
kpartx -av "${LOOP_DEV}"
sleep 2

LOOP_BASE=$(basename "${LOOP_DEV}")
ROOT_PART=""
for part in /dev/mapper/${LOOP_BASE}p*; do
    if [ -b "$part" ]; then
        FS_TYPE=$(blkid -o value -s TYPE "$part" 2>/dev/null || echo "")
        if [ "$FS_TYPE" = "ext4" ]; then
            ROOT_PART="$part"
            break
        fi
    fi
done

if [ -z "$ROOT_PART" ]; then
    echo "Error: Could not find ext4 root partition"
    exit 1
fi

MOUNT_POINT="/mnt/image"
mkdir -p "${MOUNT_POINT}"
mount "${ROOT_PART}" "${MOUNT_POINT}"

# Set up DNS
mkdir -p "${MOUNT_POINT}/run/systemd/resolve"
cat /etc/resolv.conf > "${MOUNT_POINT}/etc/resolv.conf" || \
    echo "nameserver 8.8.8.8" > "${MOUNT_POINT}/etc/resolv.conf"

mount --bind /dev "${MOUNT_POINT}/dev"
mount --bind /dev/pts "${MOUNT_POINT}/dev/pts"
mount --bind /proc "${MOUNT_POINT}/proc"
mount --bind /sys "${MOUNT_POINT}/sys"

# Step 3: Reinstall GRUB for BIOS boot (virt-resize can corrupt bootloader)
echo "=== GCE: Reinstalling GRUB for BIOS boot ==="
chroot "${MOUNT_POINT}" /bin/bash -c "
  grub-install --target=i386-pc ${LOOP_DEV}
  update-grub
"

# Step 4: Install Google guest agent for metadata processing
echo "=== GCE: Installing Google guest agent ==="
chroot "${MOUNT_POINT}" /bin/bash -c "
  set -uexo pipefail
  export DEBIAN_FRONTEND=noninteractive
  echo 'deb http://packages.cloud.google.com/apt google-compute-engine-jammy-stable main' > /etc/apt/sources.list.d/google-compute-engine.list
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  apt-get update -qq
  apt-get install -y -qq google-guest-agent google-compute-engine
  apt-get clean
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
"

# Step 5: Cleanup
echo "=== GCE: Final cleanup ==="
chroot "${MOUNT_POINT}" /bin/bash -c "
  rm -rf /var/lib/cloud
  cloud-init clean --logs || true
"
truncate -s 0 "${MOUNT_POINT}/etc/machine-id"

# Unmount
umount "${MOUNT_POINT}/sys" || true
umount "${MOUNT_POINT}/proc" || true
umount "${MOUNT_POINT}/dev/pts" || true
umount "${MOUNT_POINT}/dev" || true
umount "${MOUNT_POINT}"
kpartx -dv "${LOOP_DEV}"
losetup -d "${LOOP_DEV}"

# Step 6: Package as tar.gz for GCE
echo "=== GCE: Creating tar.gz for image import ==="
cp "${IMAGE_FILE}" disk.raw
tar -czf "postgres-${IMAGE_ARCH}-gce-image.tar.gz" disk.raw
rm disk.raw

echo "Final GCE image:"
ls -lh "postgres-${IMAGE_ARCH}-gce-image.tar.gz"

echo "=== GCE build complete ==="
echo "Upload and create GCE image with:"
echo "  gcloud storage cp postgres-${IMAGE_ARCH}-gce-image.tar.gz gs://BUCKET/postgres-${IMAGE_ARCH}-gce-image.tar.gz"
echo "  gcloud compute images create postgres-ubuntu-2204-${IMAGE_ARCH}-YYYYMMDD \\"
echo "    --source-uri=gs://BUCKET/postgres-${IMAGE_ARCH}-gce-image.tar.gz \\"
echo "    --family=postgres-ubuntu-2204 \\"
echo "    --guest-os-features=VIRTIO_SCSI_MULTIQUEUE,GVNIC"
