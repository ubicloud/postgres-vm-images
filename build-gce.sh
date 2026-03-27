#!/bin/bash
set -uexo pipefail

# Usage: ./build-gce.sh [size_gb]
# Builds a GCE-compatible PostgreSQL VM image.
# Runs the standard build (build.sh), then applies GCE-specific
# post-processing (gce-postprocess.sh):
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

# Step 2: Apply GCE-specific post-processing
./gce-postprocess.sh "postgres-${IMAGE_ARCH}-image.raw"

echo "=== GCE build complete ==="
echo "Upload and create GCE image with:"
echo "  gcloud storage cp postgres-${IMAGE_ARCH}-gce-image.tar.gz gs://BUCKET/postgres-${IMAGE_ARCH}-gce-image.tar.gz"
if [ "$IMAGE_ARCH" = "arm64" ]; then
  echo "  gcloud compute images create postgres-ubuntu-2204-${IMAGE_ARCH}-YYYYMMDD \\"
  echo "    --source-uri=gs://BUCKET/postgres-${IMAGE_ARCH}-gce-image.tar.gz \\"
  echo "    --family=postgres-ubuntu-2204 \\"
  echo "    --guest-os-features=GVNIC,UEFI_COMPATIBLE"
else
  echo "  gcloud compute images create postgres-ubuntu-2204-${IMAGE_ARCH}-YYYYMMDD \\"
  echo "    --source-uri=gs://BUCKET/postgres-${IMAGE_ARCH}-gce-image.tar.gz \\"
  echo "    --family=postgres-ubuntu-2204 \\"
  echo "    --guest-os-features=VIRTIO_SCSI_MULTIQUEUE,GVNIC"
fi
