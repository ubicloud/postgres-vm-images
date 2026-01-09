# PostgreSQL VM Images

This repository contains scripts to build PostgreSQL virtual machine images using cloud-init compatible Ubuntu base images. The image generation follows the design pattern from `ai-images` repository while implementing PostgreSQL setup steps from `postgres-images`.

## Overview

The build process:
1. Downloads Ubuntu 22.04 (Jammy) cloud image
2. Customizes it with PostgreSQL and monitoring tools using `virt-customize`
3. Produces a raw disk image ready for deployment

## What's Installed

### PostgreSQL Components
- **PostgreSQL versions**: 16, 17, and 18 (packages downloaded and cached)
- **Extensions**:
  - pg_cron, h3, hll, hypopg
  - mysql-fdw, orafce, partman
  - pgaudit, pglogical, pgrouting
  - pgtap, pgvector, postgis-3
  - pg_repack, similarity, tds-fdw
- **Additional tools**: pgbouncer
- **WAL-G**: Built from source (commit cf1ce0f5b69048e31d740b508a79d8294707e339)
- **Configuration**:
  - Data checksums enabled by default
  - Auto-cluster creation disabled
  - Custom createcluster.d directory support

### Monitoring Stack
- **Prometheus** v2.53.0
- **Node Exporter** v1.8.1 (system metrics)
- **Postgres Exporter** v0.15.0 (database metrics)

### Users and Groups
- `prometheus` - Runs Prometheus and Node Exporter
- `ubi_monitoring` - Runs Postgres Exporter
- `cert_readers` - Group for certificate access (includes postgres and prometheus)

## Prerequisites

- Ubuntu/Debian host system
- Root/sudo access
- Required packages: `guestfs-tools`, `qemu-utils`
- At least 20GB free disk space (configurable)

## Usage

### Basic Build

```bash
sudo ./build.sh
```

This creates a 20GB disk image by default.

### Custom Disk Size

```bash
sudo ./build.sh 30  # Creates a 30GB image
```

### Output

The build process produces:
- `postgres-vm-image.raw` - Raw disk image ready for deployment

## Architecture

### File Structure

```
postgres-vm-images/
├── build.sh                      # Main build orchestration script
├── setup_01.sh                   # PostgreSQL and WAL-G installation
├── setup_02.sh                   # Prometheus and monitoring tools installation
├── setup_03.sh                   # Cloud-init and system configuration (Ubicloud extras)
├── assets/                       # Configuration files and package lists
│   ├── 16.txt                    # PostgreSQL 16 package list
│   ├── 17.txt                    # PostgreSQL 17 package list
│   ├── 18.txt                    # PostgreSQL 18 package list
│   ├── common.txt                # Common PostgreSQL packages
│   ├── prometheus.service
│   ├── node_exporter.service
│   └── postgres_exporter.service
├── README.md
├── IMPLEMENTATION_MAPPING.md     # Detailed mapping from postgres-images
└── LICENSE
```

### Build Process Flow

1. **build.sh**:
   - Downloads Ubuntu cloud image
   - Resizes disk
   - Copies setup scripts and assets into image
   - Executes setup scripts inside VM
   - Cleans up and converts to raw format

2. **setup_01.sh**:
   - Updates OpenSSH
   - Adds PostgreSQL APT repository
   - Configures postgresql-common
   - Downloads PostgreSQL packages (versions 16, 17, 18)
   - Builds and installs WAL-G from source
   - Creates users and groups

3. **setup_02.sh**:
   - Installs Prometheus monitoring stack
   - Configures systemd services
   - Sets up proper permissions

4. **setup_03.sh** (Ubicloud Extras):
   - Disables Hyper-V daemon (if present)
   - Removes Azure Linux Agent (if present)
   - Cleans and reconfigures cloud-init for generic cloud use
   - Updates grub configuration for cloud deployment
   - Ensures image works across different cloud platforms

5. **Final cleanup**:
   - Removes SSH host keys (regenerated on first boot)
   - Deletes root password
   - Cleans temporary files and logs
   - Prepares image for deployment

## Differences from postgres-images

This repository uses a **direct VM customization** approach (like ai-images) instead of the **Azure Packer** approach used in postgres-images:

| Aspect | postgres-images | postgres-vm-images |
|--------|----------------|-------------------|
| Build tool | Packer (Azure ARM) | virt-customize + bash |
| Base image | Azure marketplace | Ubuntu cloud-images |
| Provisioning | Packer provisioners | Direct shell scripts |
| Complexity | High (Packer config) | Low (simple bash) |
| Cloud dependency | Azure-specific | Cloud-agnostic |
| Build time | Slower (VM spin-up) | Faster (direct customization) |

## Key Features

- **Cloud-agnostic**: Works with any infrastructure that supports raw disk images
- **Simplified build**: Uses straightforward bash scripts instead of complex Packer templates
- **Same functionality**: Implements identical PostgreSQL setup steps as postgres-images
- **Monitoring ready**: Prometheus stack pre-installed and configured
- **Flexible**: Easy to modify and extend

## Systemd Services

The following systemd services are configured but not enabled by default:

- `prometheus.service` - Prometheus monitoring system
- `node_exporter.service` - Node/system metrics exporter
- `postgres_exporter.service` - PostgreSQL metrics exporter

Enable them after deployment as needed:

```bash
systemctl enable --now prometheus
systemctl enable --now node_exporter
systemctl enable --now postgres_exporter
```

## Notes

- PostgreSQL packages are downloaded but not installed - install specific versions as needed on first boot
- SSH host keys are removed during build - generated on first boot
- Cloud-init is cleaned and ready for re-initialization
- Machine ID is cleared for proper cloud-init operation

## License

Follow the same licensing as the source repositories (ai-images and postgres-images).
