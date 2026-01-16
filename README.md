# PostgreSQL VM Images

Build scripts for creating PostgreSQL virtual machine images from Ubuntu cloud images. Supports multiple architectures (x64/arm64) and build flavors.

## Quick Start

```bash
# Build standard image (8GB disk)
sudo ./build.sh standard

# Build with custom disk size
sudo ./build.sh standard 16

# Build ParadeDB flavor
sudo ./build.sh paradedb
```

## Build Flavors

| Flavor | Description |
|--------|-------------|
| `standard` | PostgreSQL with common extensions, CloudWatch agent, ClamAV scanning |
| `paradedb` | Standard + ParadeDB extensions (pg_analytics, pg_search) |

## What's Installed

### PostgreSQL Stack
- **PostgreSQL**: Versions 16, 17, and 18 (packages cached, not installed)
- **Extensions**: pg_cron, pgvector, postgis-3, pgaudit, pglogical, pgrouting, pgtap, hypopg, pg_repack, partman, h3, hll, mysql-fdw, tds-fdw, orafce, similarity, pguint
- **WAL-G**: Built from source for backup/restore
- **pgbouncer**: Connection pooling

### Monitoring
- Prometheus v2.53.0
- Node Exporter v1.8.1
- Postgres Exporter v0.15.0

### Configuration
- Data checksums enabled by default
- Auto-cluster creation disabled
- Custom `createcluster.d` directory support

## Prerequisites

- Linux host (Ubuntu/Debian recommended)
- Root/sudo access
- Required packages: `qemu-utils`, `kpartx`, `parted`, `guestfs-tools`
- Minimum 8GB free disk space

## Architecture Support

The build script auto-detects the host architecture:
- **x86_64** → builds `postgres-<flavor>-x64-image.raw`
- **aarch64** → builds `postgres-<flavor>-arm64-image.raw`

## Repository Structure

```
postgres-vm-images/
├── build.sh                     # Main build script
├── common/                      # Shared setup scripts
│   ├── setup_base.sh            # PostgreSQL repos, users, package caching
│   ├── setup_packages.sh        # WAL-G and pguint compilation
│   ├── setup_monitoring.sh      # Prometheus stack installation
│   ├── setup_cleanup.sh         # Cloud-init and system cleanup
│   └── assets/                  # Service files and package lists
│       ├── packages/            # PostgreSQL package lists (16.txt, 17.txt, etc.)
│       ├── prometheus.service
│       ├── node_exporter.service
│       ├── postgres_exporter.service
│       └── wal-g.service
├── flavors/                     # Flavor-specific configurations
│   ├── standard/
│   │   └── setup.sh             # CloudWatch agent, ClamAV
│   └── paradedb/
│       ├── setup.sh             # ParadeDB extensions
│       └── config.sh            # Version configuration
└── .github/workflows/           # CI/CD pipelines
```

## Build Process

1. Downloads Ubuntu 22.04 (Jammy) cloud image for the detected architecture
2. Resizes disk image to specified size using `virt-resize`
3. Mounts image via loop device and chroot (native speed, no QEMU emulation)
4. Runs setup scripts:
   - `setup_base.sh`: PostgreSQL repository, users/groups, package caching
   - `setup_packages.sh`: Builds WAL-G and pguint from source
   - `setup_monitoring.sh`: Installs Prometheus monitoring stack
   - `flavors/<flavor>/setup.sh`: Flavor-specific setup
   - `setup_cleanup.sh`: Cloud-init cleanup, service configuration
5. Cleans up: removes SSH host keys, clears machine-id, zeros free space
6. Outputs raw disk image

## Systemd Services

Services are installed but not enabled by default:

```bash
systemctl enable --now prometheus
systemctl enable --now node_exporter
systemctl enable --now postgres_exporter
```

## Users and Groups

| User/Group | Purpose |
|------------|---------|
| `prometheus` | Runs Prometheus and Node Exporter |
| `ubi_monitoring` | Runs Postgres Exporter |
| `cert_readers` | Certificate access (includes postgres, prometheus) |

## Notes

- PostgreSQL packages are cached but not installed. Install specific versions on first boot.
- SSH host keys are removed during build and regenerated on first boot.
- Cloud-init is cleaned for proper re-initialization.
- Machine-id is cleared for cloud deployment compatibility.

## GitHub Actions

The repository includes CI/CD workflows for:
- Building images on x64 and arm64 runners
- Uploading to AWS AMI and Cloudflare R2
- Cleanup of old images and AMIs

## License

MIT License - see [LICENSE](LICENSE) for details.
