# Manual Build Instructions

## Prerequisites

### System Requirements
- **OS**: Ubuntu 20.04 or newer (or any Debian-based system)
- **RAM**: At least 4GB (8GB recommended)
- **Disk Space**: At least 30GB free (for cloud image download + build artifacts)
- **CPU**: x86_64 architecture
- **Privileges**: Root/sudo access

### Required Packages
The build script will install `guestfs-tools` automatically, but you may want to pre-install:

```bash
sudo apt-get update
sudo apt-get install -y guestfs-tools qemu-utils wget
```

## Running the Build

### 1. Clone/Copy the Repository

```bash
cd /path/to/postgres-vm-images
```

Make sure you have all the files:
- `build.sh`
- `setup_01.sh`, `setup_02.sh`, `setup_03.sh`
- `assets/` directory with all package lists and service files

### 2. Make Scripts Executable

```bash
chmod +x build.sh setup_01.sh setup_02.sh setup_03.sh
```

### 3. Run the Build

#### Basic build (20GB disk):
```bash
sudo ./build.sh
```

#### Custom disk size (e.g., 30GB):
```bash
sudo ./build.sh 30
```

## Build Process Overview

The script will:

1. **Install dependencies** (guestfs-tools)
2. **Download Ubuntu 22.04 cloud image** (~700MB)
3. **Resize the image** to your specified size
4. **Copy scripts and assets** into the image
5. **Update kernel** to generic HWE 6.5
6. **Install PostgreSQL** packages (16, 17, 18)
7. **Build WAL-G** from source
8. **Install Prometheus** monitoring stack
9. **Configure cloud-init** for generic cloud deployment
10. **Clean up** and prepare for deployment
11. **Convert to RAW format**

## Build Time

Expect the build to take **30-60 minutes** depending on:
- Network speed (for downloads)
- CPU performance (for WAL-G compilation)
- Disk I/O speed

## Output

After successful build, you'll find:
- `postgres-vm-image.raw` - The final VM image (~20GB or your specified size)
- `cloud.img` - Intermediate qcow2 image (can be deleted)

## Troubleshooting

### Permission Denied

If you see permission errors:
```bash
sudo chmod 0644 /boot/vmlinuz*
sudo chmod 0666 /dev/kvm
```

### KVM Not Available

If `/dev/kvm` doesn't exist, the build will still work but may be slower. To enable KVM:
```bash
# Check if KVM is available
lsmod | grep kvm

# If not loaded, load it
sudo modprobe kvm
sudo modprobe kvm_intel  # or kvm_amd for AMD CPUs
```

### Out of Disk Space

If you run out of space during build:
1. Clean up old images: `rm -f *.img *.raw`
2. Check available space: `df -h`
3. Ensure you have at least 30GB free

### guestfs-tools Issues

If virt-customize fails:
```bash
# Update libguestfs
sudo apt-get update
sudo apt-get install -y libguestfs-tools

# Fix kernel permissions
sudo chmod 0644 /boot/vmlinuz*
```

### Network Issues During Build

If downloads fail (WAL-G, Prometheus, etc.):
- Check internet connectivity
- Check if GitHub is accessible
- Try running the build again (it will resume from where it failed)

## Verifying the Build

### Check Image Size
```bash
ls -lh postgres-vm-image.raw
```

### Inspect Image Contents (optional)
```bash
# View installed packages
virt-customize -a postgres-vm-image.raw --run-command "dpkg -l | grep postgres"

# Check kernel version
virt-customize -a postgres-vm-image.raw --run-command "ls /boot/vmlinuz*"

# View disk usage
virt-df -h postgres-vm-image.raw
```

## Testing the Image

To test the image locally with QEMU:

```bash
# Install QEMU
sudo apt-get install -y qemu-system-x86

# Run the VM (basic test)
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -smp 2 \
  -drive file=postgres-vm-image.raw,format=raw \
  -nographic \
  -serial mon:stdio
```

## Deployment

The resulting `postgres-vm-image.raw` can be:
1. Uploaded to your cloud provider
2. Converted to other formats (qcow2, vmdk, vhd)
3. Used directly with QEMU/KVM

### Convert to Other Formats

```bash
# To QCOW2
qemu-img convert -f raw -O qcow2 postgres-vm-image.raw postgres-vm-image.qcow2

# To VHD (Azure/Hyper-V)
qemu-img convert -f raw -O vpc postgres-vm-image.raw postgres-vm-image.vhd

# To VMDK (VMware)
qemu-img convert -f raw -O vmdk postgres-vm-image.raw postgres-vm-image.vmdk
```

## Cleanup

After successful build and deployment:

```bash
# Remove intermediate files
rm -f cloud.img

# Keep the RAW image for deployment
# rm -f postgres-vm-image.raw  # Only remove after uploading to your infrastructure
```

## Notes

- The build must be run with `sudo` because virt-customize requires root privileges
- The script uses `set -uexo pipefail` which means it will stop on any error
- All temporary files inside the VM are cleaned up automatically
- SSH host keys are removed and will be regenerated on first boot
- cloud-init is reset and ready for initialization on first boot
