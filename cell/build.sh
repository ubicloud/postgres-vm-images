#!/bin/bash
# Build the two images a Postgres cell runs from:
#
#   cell-root-<pgver>.raw    read-only root shared by every cell VM
#   cell-pgdata-<pgver>.raw  ext4 holding a freshly initdb'd cluster
#
# Nothing in the guest listens for the host. The data disk's hot-plug drives
# everything through udev and systemd:
#
#   hot-plug -> cell-restore-hook (reseed the CRNG from virtio-rng, set the
#   clock from ptp_kvm) -> fsck -> /data -> cell-postgres.service
#
# celld configures PostgreSQL over SQL from the slot's tap address, which the
# PGDATA image's pg_hba trusts for the postgres role, and pauses a cell with
# the ACPI power button.
#
# Usage: sudo ./cell/build.sh [pg_version] [root_size_gb] [pgdata_size_mb]
# Example: sudo ./cell/build.sh 18 6 1536
#
# Runs as root on an x86_64 machine with loop devices. Derived from the Ubuntu
# noble cloud image, the same base the control plane's ubuntu-noble boot image
# is. Set BASE to a local raw copy of that image to skip the download.
set -euo pipefail

PGVER="${1:-18}"
ROOT_SIZE_GB="${2:-6}"
PGDATA_SIZE_MB="${3:-1536}"

UBUNTU_CODENAME="${UBUNTU_CODENAME:-noble}"
UBUNTU_ARCH=amd64
BASE="${BASE:-}"
OUT="${OUT:-$PWD}"
WORK="${WORK:-}"
MNT=/mnt/cellroot
ROOT_IMG="$OUT/cell-root-$PGVER.raw"
PGDATA_IMG="$OUT/cell-pgdata-$PGVER.raw"
HERE=$(cd "$(dirname "$0")" && pwd)
GUEST="$HERE/guest"

log() { echo "[$(date +%T)] $*"; }

if [[ $(uname -m) != x86_64 ]]; then
  echo "Error: cell images are x86_64 only (restore checks CPUID against the snapshot's host)"
  exit 1
fi

mkdir -p "$OUT" "$MNT"
WORK_IS_TEMP=
if [[ -z "$WORK" ]]; then
  WORK=$(mktemp -d "$OUT/.cell-build.XXXXXX")
  WORK_IS_TEMP=1
fi
mkdir -p "$WORK"

cleanup() {
  set +e
  mountpoint -q "$MNT/data" && umount "$MNT/data"
  for d in dev/pts dev proc sys run; do mountpoint -q "$MNT/$d" && umount -l "$MNT/$d"; done
  mountpoint -q "$MNT/boot/efi" && umount "$MNT/boot/efi"
  mountpoint -q "$MNT/boot" && umount "$MNT/boot"
  mountpoint -q "$MNT" && umount "$MNT"
  [[ -n "${PGLOOP:-}" ]] && losetup -d "$PGLOOP"
  [[ -n "${LOOP:-}" ]] && losetup -d "$LOOP"
}
remove_work() { if [[ -n "$WORK_IS_TEMP" ]]; then rm -rf "$WORK"; fi; }
trap 'cleanup; remove_work' EXIT

log "PostgreSQL $PGVER, root ${ROOT_SIZE_GB}G, PGDATA ${PGDATA_SIZE_MB}M, base $UBUNTU_CODENAME"

# Lock::Timeout waits out the runner's unattended-upgrades (apt-daily timers
# fire on a randomized schedule) instead of failing on a held dpkg lock.
apt-get -o DPkg::Lock::Timeout=300 update
apt-get -o DPkg::Lock::Timeout=300 install -y qemu-utils gdisk fdisk util-linux e2fsprogs gcc libc6-dev curl

log "compiling the restore hook"
gcc -O2 -static -Wall -Werror -o "$WORK/cell-restore-hook" "$GUEST/cell-restore-hook.c"

if [[ -z "$BASE" ]]; then
  log "downloading the $UBUNTU_CODENAME cloud image"
  curl -fL -o "$WORK/cloud.img" \
    "https://cloud-images.ubuntu.com/${UBUNTU_CODENAME}/current/${UBUNTU_CODENAME}-server-cloudimg-${UBUNTU_ARCH}.img"
  qemu-img convert -f qcow2 -O raw "$WORK/cloud.img" "$WORK/root.raw"
  rm -f "$WORK/cloud.img"
else
  log "copying base image $BASE"
  rm -f "$WORK/root.raw"
  cp --sparse=always "$BASE" "$WORK/root.raw"
fi

log "growing image to ${ROOT_SIZE_GB}G and extending partition 1"
truncate -s "${ROOT_SIZE_GB}G" "$WORK/root.raw"
sgdisk -e "$WORK/root.raw" >/dev/null
echo ", +" | sfdisk -N 1 --no-reread --force "$WORK/root.raw" >/dev/null

LOOP=$(losetup -f --show -P "$WORK/root.raw")
log "loop=$LOOP"
for _ in $(seq 50); do [[ -e "${LOOP}p1" ]] && break; partx -u "$LOOP" 2>/dev/null || true; udevadm settle 2>/dev/null || true; sleep 0.2; done
[[ -e "${LOOP}p1" ]] || { echo "partition nodes for $LOOP never appeared"; exit 1; }
e2fsck -fp "${LOOP}p1" >/dev/null 2>&1 || true
resize2fs "${LOOP}p1" >/dev/null

# Noble and later split /boot (p16) and /boot/efi (p15) off the root (p1).
mount "${LOOP}p1" "$MNT"
mount "${LOOP}p16" "$MNT/boot"
mount "${LOOP}p15" "$MNT/boot/efi"
for d in dev dev/pts proc sys run; do mount --bind "/$d" "$MNT/$d"; done
# The image's resolv.conf is a symlink into /run, which is the build machine's
# here; a plain file for the duration of the build keeps DNS inside the chroot
# and the machine's own resolver untouched. The symlink comes back at the end.
RESOLV_LINK=$(readlink "$MNT/etc/resolv.conf" || true)
rm -f "$MNT/etc/resolv.conf"
printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "$MNT/etc/resolv.conf"

log "installing the hot-plug chain"
install -m 0755 "$WORK/cell-restore-hook" "$MNT/usr/local/sbin/cell-restore-hook"
install -m 0644 "$GUEST/90-cell-data.rules" "$MNT/etc/udev/rules.d/90-cell-data.rules"
for unit in cell-restore-hook.service data.mount cell-fast-off.service; do
  install -m 0644 "$GUEST/$unit" "$MNT/etc/systemd/system/$unit"
done
for unit in cell-postgres.service cell-template-ready.service; do
  sed "s/@PGVER@/$PGVER/g" "$GUEST/$unit" > "$MNT/etc/systemd/system/$unit"
done
FSCK_DROPIN="$MNT/etc/systemd/system/systemd-fsck@dev-disk-by\\x2did-virtio\\x2dcldata.service.d"
mkdir -p "$FSCK_DROPIN"
install -m 0644 "$GUEST/fsck-after-restore-hook.conf" "$FSCK_DROPIN/after-restore-hook.conf"
printf 'ptp_kvm\nvirtio-rng\n' > "$MNT/etc/modules-load.d/cell.conf"

# The rest of the storage stack runs on every new block device and has
# nothing to find on a cell's data disk; snapd's auto-import alone put a
# process spawn between the hot-plug and the mount.
for rule in 66-snapd-autoimport 56-lvm 69-lvm 60-multipath 56-dm-mpath 63-md-raid-arrays \
    64-md-raid-assembly 69-md-clustered-confirm-device 64-btrfs 66-azure-ephemeral 69-bcache \
    80-udisks2 85-hdparm 90-iocost 95-kpartx 96-e2scrub 68-del-part-nodes \
    61-persistent-storage-android; do
  ln -sf /dev/null "$MNT/etc/udev/rules.d/$rule.rules"
done

log "installing PostgreSQL $PGVER and configuring guest"
cat > "$MNT/tmp/chroot-setup.sh" <<CHROOT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# /run is the build machine's, bind-mounted, so systemctl would otherwise
# find the machine's own systemd and stop its services rather than the image's.
export SYSTEMD_OFFLINE=1
install -d /usr/share/postgresql-common/pgdg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $UBUNTU_CODENAME-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
apt-get update -qq
apt-get install -y -qq --no-install-recommends postgresql-$PGVER postgresql-contrib-$PGVER

# ptp_kvm, which the restore hook reads the host's clock through, is in
# linux-modules-extra; take that one module rather than the whole package.
# The archive drops superseded kernels, so fall back to Launchpad, which keeps
# every build.
KVER=\$(ls /lib/modules)
KPKG=\$(dpkg-query -W -f='\${Version}' linux-modules-\$KVER)
cd /tmp
apt-get download -qq linux-modules-extra-\$KVER 2>/dev/null ||
  curl -fsSLO "https://launchpad.net/ubuntu/+archive/primary/+files/linux-modules-extra-\${KVER}_\${KPKG}_${UBUNTU_ARCH}.deb"
dpkg-deb --fsys-tarfile /tmp/linux-modules-extra-\${KVER}_*.deb \
  | tar -x -C / ./lib/modules/\$KVER/kernel/drivers/ptp/ptp_kvm.ko.zst
rm -f /tmp/linux-modules-extra-*.deb
depmod -a \$KVER

# The packaged units never run: the cluster lives on the data disk, and
# cell-postgres.service starts it when the disk arrives.
systemctl disable postgresql >/dev/null 2>&1 || true
systemctl mask postgresql postgresql@$PGVER-main >/dev/null 2>&1 || true
rm -f /etc/postgresql/$PGVER/main/postgresql.conf.orig
pg_dropcluster --stop $PGVER main >/dev/null 2>&1 || true

systemctl enable cell-fast-off.service cell-template-ready.service >/dev/null

# No datasource, no per-boot network config: every cell boots identical.
touch /etc/cloud/cloud-init.disabled
rm -f /etc/netplan/50-cloud-init.yaml
cat > /etc/netplan/10-cell.yaml <<'NETPLAN'
network:
  version: 2
  ethernets:
    clnic:
      match:
        macaddress: "02:5b:0c:00:00:02"
      set-name: clnic
      dhcp4: false
      dhcp6: false
      accept-ra: false
      addresses: [fd00:b1c:5b0c::2/64, 10.255.255.2/30]
      routes:
        - to: default
          via: fd00:b1c:5b0c::1
NETPLAN
chmod 600 /etc/netplan/10-cell.yaml

# Trim boot work that has no place in a snapshot restored hundreds of times.
systemctl disable unattended-upgrades apt-daily.timer apt-daily-upgrade.timer \
  man-db.timer motd-news.timer e2scrub_all.timer fstrim.timer systemd-networkd-wait-online \
  snapd.seeded.service snapd.service snapd.socket multipathd.service multipathd.socket \
  ssh.service ssh.socket >/dev/null 2>&1 || true
# Anything that wakes up on a timer or reacts to the clock jump on resume is
# work every restored clone would repeat. The cell needs none of it: the
# restore hook sets the clock, there is no DNS, and packet filtering lives on
# the host. The rest are units a power-off would otherwise stop one by one.
systemctl mask systemd-networkd-wait-online.service systemd-timesyncd.service \
  systemd-resolved.service ufw.service cron.service rsyslog.service \
  apport.service plymouth-start.service plymouth-quit.service plymouth-quit-wait.service \
  plymouth-read-write.service systemd-update-utmp-runlevel.service \
  ModemManager.service udisks2.service finalrd.service lvm2-monitor.service polkit.service \
  open-iscsi.service iscsid.service blk-availability.service \
  >/dev/null 2>&1 || true

# Journald volatile: the root is read-only anyway, this keeps it honest.
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=volatile\nRuntimeMaxUse=32M\n' > /etc/systemd/journald.conf.d/cell.conf

mkdir -p /data
echo 'overlayroot="tmpfs:swap=0,recurse=0"' > /etc/overlayroot.conf
echo 'overlayroot_cfgdisk="disabled"' >> /etc/overlayroot.conf

id -u postgres > /tmp/pg_uid
id -g postgres > /tmp/pg_gid
update-initramfs -u -k all >/dev/null 2>&1
apt-get clean
CHROOT
chroot "$MNT" bash /tmp/chroot-setup.sh
PG_UID=$(cat "$MNT/tmp/pg_uid"); PG_GID=$(cat "$MNT/tmp/pg_gid")
log "guest postgres uid=$PG_UID gid=$PG_GID"

cat > "$MNT/tmp/initdb.sh" <<CHROOT2
set -euo pipefail
su -s /bin/sh postgres -c "/usr/lib/postgresql/$PGVER/bin/initdb -D /data/pgdata \
  --data-checksums -E UTF8 --locale=C.UTF-8 --auth-local=peer --auth-host=scram-sha-256 -U postgres" >/dev/null
mkdir -p /data/pgdata/conf.d
cat >> /data/pgdata/postgresql.conf <<'PGCONF'

# --- cell settings ---
listen_addresses = 'fd00:b1c:5b0c::2,localhost'
port = 5432
max_connections = 30
shared_buffers = 64MB
work_mem = 4MB
maintenance_work_mem = 32MB
effective_cache_size = 256MB
wal_level = minimal
max_wal_senders = 0
max_wal_size = 256MB
checkpoint_timeout = 5min
temp_file_limit = 512MB
log_destination = 'stderr'
logging_collector = off
password_encryption = scram-sha-256
fsync = on
include_dir = 'conf.d'
PGCONF
# The first line is celld's: the slot's tap address, which only a process in
# the slot's network namespace on the host can connect from. Everyone else,
# the gateways included, gets a password prompt.
cat > /data/pgdata/pg_hba.conf <<'PGHBA'
host    all   postgres   fd00:b1c:5b0c::1/128   trust
local   all   postgres                          peer
local   all   all                               scram-sha-256
host    all   all        ::/0                   scram-sha-256
host    all   all        0.0.0.0/0              scram-sha-256
PGHBA
chown -R postgres:postgres /data/pgdata
chmod 700 /data/pgdata
CHROOT2

# Journalled: a cell is paused and killed abruptly by definition, and a
# non-journalled PGDATA did not survive the first unclean kill.
log "building PGDATA image (${PGDATA_SIZE_MB}M)"
rm -f "$WORK/pgdata.raw"
truncate -s "${PGDATA_SIZE_MB}M" "$WORK/pgdata.raw"
mkfs.ext4 -q -F -m 0 -L cldata "$WORK/pgdata.raw"
PGLOOP=$(losetup -f --show "$WORK/pgdata.raw")
mount "$PGLOOP" "$MNT/data"
chown "$PG_UID:$PG_GID" "$MNT/data"
chroot "$MNT" bash /tmp/initdb.sh
sync
umount "$MNT/data"
losetup -d "$PGLOOP"; PGLOOP=
cp --sparse=always "$WORK/pgdata.raw" "$PGDATA_IMG"
log "  $(basename "$PGDATA_IMG"): $(du -h --apparent-size "$PGDATA_IMG" | cut -f1) apparent, $(du -h "$PGDATA_IMG" | cut -f1) actual"

log "finalising root image"
rm -f "$MNT/tmp/chroot-setup.sh" "$MNT/tmp/initdb.sh" "$MNT/tmp/pg_uid" "$MNT/tmp/pg_gid"
rm -rf "$MNT/var/lib/apt/lists/"*
rm -f "$MNT/etc/resolv.conf"
if [[ -n "$RESOLV_LINK" ]]; then ln -s "$RESOLV_LINK" "$MNT/etc/resolv.conf"; fi
fstrim "$MNT" || true
fstrim "$MNT/boot" || true
sync
cleanup
trap - EXIT
cp --sparse=always "$WORK/root.raw" "$ROOT_IMG"
log "  $(basename "$ROOT_IMG"): $(du -h --apparent-size "$ROOT_IMG" | cut -f1) apparent, $(du -h "$ROOT_IMG" | cut -f1) actual"
remove_work
log done
