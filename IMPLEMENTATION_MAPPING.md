# Implementation Details

This document describes the PostgreSQL VM image build implementation.

## Build Architecture

The build uses a **direct mount + chroot** approach:

1. **virt-resize** - Only used for initial image resizing (fast, no VM boot)
2. **Loop mount + chroot** - All script execution runs at native CPU speed

This approach is significantly faster than QEMU-based builds, especially on ARM64 where QEMU emulation would be extremely slow.

## Setup Scripts

### common/setup_base.sh
- Adds PostgreSQL APT repository (apt.postgresql.org)
- Adds golang PPA for WAL-G build
- Installs postgresql-common
- Configures createcluster.conf (data checksums, no auto cluster)
- Downloads PostgreSQL packages for versions 16, 17, 18
- Creates users: prometheus, ubi_monitoring
- Creates cert_readers group

### common/setup_packages.sh
- Installs build tools (golang-go, cmake)
- Installs Python and PostgreSQL dev packages
- **Builds WAL-G from source** (commit cf1ce0f5b69048e31d740b508a79d8294707e339)
- Builds walg-daemon-client
- **Builds pguint extension** for PG 16, 17, 18

### common/setup_monitoring.sh
- Downloads and installs Prometheus v2.53.0
- Downloads and installs node_exporter v1.8.1
- Downloads and installs postgres_exporter v0.15.0
- Installs systemd service files

### common/setup_cleanup.sh
- Cleans apt cache
- Removes unnecessary packages
- General cleanup

### flavors/{flavor}/setup.sh
- Flavor-specific setup (e.g., ParadeDB extensions)

## Final Cleanup (in build.sh)

- Removes SSH host keys (regenerated on first boot)
- Deletes root password
- Cleans package cache and logs
- Cleans cloud-init state
- Zero-fills free space for compression
- Truncates machine-id

## Installed Components

### PostgreSQL
- Versions: 16, 17, 18 (packages downloaded, not installed)
- Extensions: pguint (built from source for each version)

### WAL-G
- Built from source for native architecture
- Includes walg-daemon-client

### Monitoring Stack
| Component | Version |
|-----------|---------|
| Prometheus | 2.53.0 |
| node_exporter | 1.8.1 |
| postgres_exporter | 0.15.0 |

### Users & Groups
| User/Group | Purpose |
|------------|---------|
| prometheus | Prometheus daemon |
| ubi_monitoring | Monitoring access |
| cert_readers | Certificate access group |

## GitHub Actions Workflow

The workflow (`postgres-vm-image.yml`) supports:

- **Architectures**: x64, ARM64
- **Flavors**: standard, paradedb
- **Upload targets**: MinIO, Cloudflare R2, AWS AMI
- **AWS regions**: Configurable multi-region AMI copies

### Workflow Inputs

| Input | Description |
|-------|-------------|
| `flavor` | Image flavor (standard/paradedb) |
| `image_suffix` | Version suffix (e.g., 20260115.1.0) |
| `image_resize_gb` | Final image size |
| `upload_image` | Upload to MinIO |
| `upload_r2` | Upload to Cloudflare R2 |
| `upload_aws_ami` | Create AWS AMI |
| `aws_ami_regions` | Regions for AMI copies |
| `build_arm64` | Build ARM64 in addition to x64 |
