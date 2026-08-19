# Implementation Details

This document describes the PostgreSQL VM image build implementation.

## Build Architecture

The build uses a **direct mount + chroot** approach:

1. **virt-resize** - Only used for initial image resizing (fast, no VM boot)
2. **Loop mount + chroot** - All script execution runs at native CPU speed

This approach is significantly faster than QEMU-based builds, especially on ARM64 where QEMU emulation would be extremely slow.

## Setup Scripts

### common/setup_base.sh
- Pins GNU coreutils and classic sudo (Ubuntu 25.10+ default to uutils/sudo-rs)
- Installs the latest HWE generic kernel for the release
- Adds PostgreSQL APT repository (apt.postgresql.org)
- Adds golang PPA for WAL-G build
- Installs postgresql-common
- Configures createcluster.conf (data checksums, no auto cluster)
- Downloads PostgreSQL packages for versions 16, 17, 18
- Creates users: prometheus, ubi_monitoring
- Creates cert_readers group
- Sets up IMDS protection (nftables)

### common/setup_packages.sh
- Installs build tools (golang-go, cmake)
- Installs Python and PostgreSQL dev packages
- **Builds WAL-G from source** (see pinned commit in the script)
- Builds walg-daemon-client
- **Builds pguint extension** for PG 16, 17, 18
- **Builds walg_archive extension** for PG 16, 17, 18
- Installs pg_textsearch for PG 17, 18

### common/setup_monitoring.sh
- Downloads and installs Prometheus, node_exporter, postgres_exporter
  and otelcol-contrib (see pinned versions in the script)
- Installs CloudWatch and GuardDuty agents
- Installs systemd service files
- Runs a ClamAV scan of system binaries

### common/setup_cleanup.sh
- Cleans cloud-init state for first-boot re-initialization
- Configures the cloud-init datasource list and grub serial console

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
- Extensions: pguint, walg_archive (built from source for each version)

### WAL-G
- Built from source for native architecture
- Includes walg-daemon-client

### Monitoring Stack
| Component | Version |
|-----------|---------|
| Prometheus | 3.5.2 |
| node_exporter | 1.11.1 |
| postgres_exporter | 0.19.1 |
| otelcol-contrib | 0.150.1 |

### Users & Groups
| User/Group | Purpose |
|------------|---------|
| prometheus | Prometheus daemon |
| ubi_monitoring | Monitoring access |
| cert_readers | Certificate access group |

## GitHub Actions Workflow

The workflow (`postgres-vm-image.yml`) supports:

- **Architectures**: x64, ARM64
- **Upload targets**: MinIO, Cloudflare R2, AWS AMI, GCE
- **AWS regions**: Configurable multi-region AMI copies

### Workflow Inputs

| Input | Description |
|-------|-------------|
| `image_suffix` | Version suffix (e.g., 20260115.1.0) |
| `image_resize_gb` | Final image size |
| `ubuntu_release` | Ubuntu release to build on (2604/2204) |
| `upload_image` | Upload to MinIO |
| `upload_r2` | Upload to Cloudflare R2 |
| `upload_aws_ami` | Create AWS AMI |
| `upload_gce` | Create GCE image |
| `aws_ami_regions` | Regions for AMI copies |
| `build_arm64` | Build ARM64 in addition to x64 |
| `create_ubicloud_pr` | Open an image-update PR against ubicloud/ubicloud |
