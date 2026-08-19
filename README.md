# PostgreSQL VM Images

Build scripts for creating PostgreSQL virtual machine images from Ubuntu cloud images. Supports multiple architectures (x64/arm64).

## Quick Start

```bash
# Build image (12GB disk, apt upgrade, Ubuntu 26.04)
sudo ./build.sh

# Build with custom disk size
sudo ./build.sh 16

# Full argument form: size_gb, run_apt_upgrade, ubuntu_release
sudo ./build.sh 12 true 2604
```

## Ubuntu Release

Images are built on **Ubuntu 26.04 LTS (resolute)** by default. The release is
parameterized (`ubuntu_release` build argument / workflow input); `2204`
(jammy) remains selectable for rebuilding the previous image family during the
migration window. Adding a new release requires extending the release cases in
`build.sh` and `common/setup_base.sh` (per-release library package names).

On 25.10+ releases the build pins **GNU coreutils and classic sudo** in place
of the uutils/sudo-rs defaults, since the control plane drives PostgreSQL
through sudo and coreutils and depends on exact GNU behavior.

## What's Installed

### PostgreSQL Stack
- **PostgreSQL**: Versions 16, 17, and 18 (packages cached, not installed)
- **Extensions**: pg_cron, pgvector, postgis-3, pgaudit, pglogical, pgrouting, pgtap, hypopg, pg_repack, partman, h3, hll, mysql-fdw, tds-fdw, orafce, similarity, pguint, VectorChord, pg_tokenizer, VectorChord-bm25, pg_textsearch (17/18)
- **WAL-G**: Built from source for backup/restore (plus walg_archive extension)
- **pgbouncer**: Connection pooling

### Monitoring
- Prometheus v3.5.2
- Node Exporter v1.11.1
- Postgres Exporter v0.19.1
- OpenTelemetry Collector (contrib)
- CloudWatch agent, GuardDuty agent (AWS), ClamAV scan at build time

### Configuration
- Data checksums enabled by default
- Auto-cluster creation disabled
- Custom `createcluster.d` directory support

## Prerequisites

- Linux host (Ubuntu 24.04 or newer recommended)
- Root/sudo access
- Required packages: `qemu-utils`, `kpartx`, `parted`, `guestfs-tools`
- Minimum 12GB free disk space

## Architecture Support

The build script auto-detects the host architecture:
- **x86_64** → builds `postgres-x64-image.raw`
- **aarch64** → builds `postgres-arm64-image.raw`

## Repository Structure

```
postgres-vm-images/
├── build.sh                     # Main build script
├── gce-postprocess.sh           # GCE-specific post-processing (grub, guest agent)
├── common/                      # Shared setup scripts
│   ├── setup_base.sh            # PostgreSQL repos, users, package caching
│   ├── setup_packages.sh        # WAL-G, pguint, walg_archive compilation
│   ├── setup_monitoring.sh      # Prometheus stack installation
│   ├── setup_cleanup.sh         # Cloud-init and system cleanup
│   └── assets/                  # Service files and package lists
│       ├── packages/            # PostgreSQL package lists (16.txt, 17.txt, etc.)
│       ├── scripts/             # Runtime helper scripts
│       ├── prometheus.service
│       ├── node_exporter.service
│       ├── postgres_exporter.service
│       └── wal-g.service
└── .github/workflows/           # CI/CD pipelines
```

## Build Process

1. Downloads the Ubuntu cloud image for the selected release and detected architecture
2. Resizes disk image to specified size using `virt-resize`
3. Mounts image via loop device and chroot (native speed, no QEMU emulation);
   on 24.04+ images this includes the separate `/boot` and `/boot/efi` partitions
4. Runs setup scripts:
   - `setup_base.sh`: GNU userland pin, kernel, PostgreSQL repository, users/groups, package caching
   - `setup_packages.sh`: Builds WAL-G, pguint, and walg_archive from source
   - `setup_monitoring.sh`: Installs monitoring stack and AWS agents
   - `setup_cleanup.sh`: Cloud-init cleanup, grub configuration
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
- Uploading to MinIO, Cloudflare R2, AWS AMI, and GCE
- Creating image-update PRs against ubicloud/ubicloud
- Cleanup of old images and AMIs

## License

MIT License - see [LICENSE](LICENSE) for details.
