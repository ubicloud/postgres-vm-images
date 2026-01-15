# Manual Build Instructions

## Prerequisites

### System Requirements
- **OS**: Ubuntu 22.04 or newer
- **RAM**: At least 4GB (8GB recommended)
- **Disk Space**: At least 20GB free
- **CPU**: x86_64 or ARM64 architecture
- **Privileges**: Root/sudo access

### Required Packages
The build script will install dependencies automatically, but you can pre-install:

```bash
sudo apt-get update
sudo apt-get install -y qemu-utils kpartx parted guestfs-tools
```

## Repository Structure

```
postgres-vm-images/
├── build.sh                 # Main build script
├── common/
│   ├── setup_base.sh        # PostgreSQL repos & base packages
│   ├── setup_packages.sh    # WAL-G & pguint compilation
│   ├── setup_monitoring.sh  # Prometheus stack
│   ├── setup_cleanup.sh     # Final cleanup
│   └── assets/              # Package lists & service files
└── flavors/
    ├── standard/            # Standard PostgreSQL image
    └── paradedb/            # ParadeDB flavor
```

## Running the Build

### Basic Usage

```bash
# Build standard flavor with 8GB disk
sudo ./build.sh standard 8

# Build paradedb flavor with 10GB disk
sudo ./build.sh paradedb 10
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `flavor` | `standard` | Image flavor (standard, paradedb) |
| `size_gb` | `8` | Final image size in GB |

## Build Process

The build uses a **direct mount + chroot** approach for native-speed execution:

1. **Download** Ubuntu 22.04 cloud image
2. **Resize** image using virt-resize (only libguestfs operation)
3. **Mount** image via loop device + kpartx
4. **Chroot** into mounted filesystem
5. **Execute** setup scripts at native CPU speed:
   - `setup_base.sh` - PostgreSQL APT repo, base packages
   - `setup_packages.sh` - Build WAL-G and pguint from source
   - `setup_monitoring.sh` - Prometheus, node_exporter, postgres_exporter
   - Flavor-specific `setup.sh`
   - `setup_cleanup.sh` - Clean apt cache, logs
6. **Cleanup** - Zero-fill, unmount, detach loop device

## Build Time

| Architecture | Typical Time |
|--------------|--------------|
| x86_64 | ~12-15 minutes |
| ARM64 | ~18-22 minutes |

WAL-G compilation is the longest step (~5-8 minutes).

## Output

After successful build:
```
postgres-standard-x64-image.raw    # x86_64 build
postgres-standard-arm64-image.raw  # ARM64 build
```

## Troubleshooting

### Permission Denied on /boot/vmlinuz*
```bash
sudo chmod 0644 /boot/vmlinuz*
```

### Loop Device Issues
```bash
# List active loop devices
losetup -a

# Clean up stale mappings
sudo kpartx -d /dev/loopX
sudo losetup -d /dev/loopX
```

### Build Fails Mid-Way
```bash
# Clean up mounts
sudo umount -R /mnt/image 2>/dev/null
sudo kpartx -d /dev/loop* 2>/dev/null
sudo losetup -D

# Remove partial files
rm -f cloud.img cloud.raw resized.img
```

## Testing Locally

```bash
# Run with QEMU
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -drive file=postgres-standard-x64-image.raw,format=raw \
  -nographic
```

## Converting to Other Formats

```bash
# To QCOW2 (smaller file size)
qemu-img convert -f raw -O qcow2 image.raw image.qcow2

# To VHD (Azure/Hyper-V)
qemu-img convert -f raw -O vpc image.raw image.vhd
```
