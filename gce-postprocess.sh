#!/bin/bash
set -uexo pipefail

# Usage: ./gce-postprocess.sh <raw-image-path>
# Applies GCE-specific post-processing to a raw disk image:
#   1. GRUB reinstall for BIOS boot (virt-resize can corrupt it)
#   2. Google guest agent for metadata/SSH/startup-script support
#   3. Tar.gz packaging for gcloud compute images create
#
# The raw image is modified in place.
# Outputs: postgres-{arch}-gce-image.tar.gz in the current directory.

IMAGE_FILE="${1:?Usage: gce-postprocess.sh <raw-image-path>}"

HOST_ARCH=$(uname -m)
case $HOST_ARCH in
  x86_64)  IMAGE_ARCH="x64" ;;
  aarch64) IMAGE_ARCH="arm64" ;;
  *)       echo "Unsupported architecture: $HOST_ARCH"; exit 1 ;;
esac

echo "=== GCE post-processing: ${IMAGE_FILE} ==="

# Step 1: Mount image and apply GCE-specific fixes
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

# Step 2: Reinstall GRUB (architecture-specific)
if [ "$HOST_ARCH" = "x86_64" ]; then
  echo "=== GCE: Reinstalling GRUB for BIOS boot (x86_64) ==="
  chroot "${MOUNT_POINT}" /bin/bash -c "
    grub-install --target=i386-pc ${LOOP_DEV}
    update-grub
  "
else
  echo "=== GCE: Updating GRUB for EFI boot (arm64) ==="
  # ARM64 uses UEFI boot - the EFI partition from the Ubuntu cloud image
  # is already correct. Just update grub config.
  # Mount the EFI partition if present
  EFI_PART=""
  for part in /dev/mapper/${LOOP_BASE}p*; do
    if [ -b "$part" ]; then
      FS_TYPE=$(blkid -o value -s TYPE "$part" 2>/dev/null || echo "")
      if [ "$FS_TYPE" = "vfat" ]; then
        EFI_PART="$part"
        break
      fi
    fi
  done
  if [ -n "$EFI_PART" ]; then
    mkdir -p "${MOUNT_POINT}/boot/efi"
    mount "$EFI_PART" "${MOUNT_POINT}/boot/efi"
    chroot "${MOUNT_POINT}" /bin/bash -c "update-grub"
    umount "${MOUNT_POINT}/boot/efi"
  else
    chroot "${MOUNT_POINT}" /bin/bash -c "update-grub"
  fi
fi

# Step 3: Install Google guest agent for metadata processing
echo "=== GCE: Installing Google guest agent ==="
chroot "${MOUNT_POINT}" /bin/bash -c "
  set -uexo pipefail
  export DEBIAN_FRONTEND=noninteractive
  apt-add-repository -y universe
  apt-get update -qq
  apt-get install -y -qq google-guest-agent google-compute-engine
  apt-get clean
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
"

# Step 4: Cleanup
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

# Step 5: Package as tar.gz for GCE
echo "=== GCE: Creating tar.gz for image import ==="
cp "${IMAGE_FILE}" disk.raw
tar -czf "postgres-${IMAGE_ARCH}-gce-image.tar.gz" disk.raw
rm disk.raw

echo "Final GCE image:"
ls -lh "postgres-${IMAGE_ARCH}-gce-image.tar.gz"

echo "=== GCE post-processing complete ==="
