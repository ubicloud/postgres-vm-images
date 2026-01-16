#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== [setup_cleanup.sh] Configuring cloud-init and grub ==="

# Clean up cloud-init logs and cache to run it again on first boot
cloud-init clean --logs --seed

# Configure cloud-init datasource list for multi-cloud compatibility
cat > /etc/cloud/cloud.cfg.d/90_dpkg.cfg <<'EOF'
# to update this file, run dpkg-reconfigure cloud-init
datasource_list: [ NoCloud, ConfigDrive, OpenNebula, DigitalOcean, Azure, AltCloud, OVF, MAAS, GCE, OpenStack, CloudSigma, SmartOS, Bigstep, Scaleway, AliYun, Ec2, CloudStack, Hetzner, IBMCloud, Oracle, Exoscale, RbxCloud, UpCloud, VMware, Vultr, LXD, NWCS, None ]
EOF

# Configure grub for cloud deployment (serial console access)
mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/50-cloudimg-settings.cfg <<'EOF'
# Cloud Image specific Grub settings for Generic Cloud Images

# Set the recordfail timeout
GRUB_RECORDFAIL_TIMEOUT=0

# Do not wait on grub prompt
GRUB_TIMEOUT=0

# Set the default commandline
GRUB_CMDLINE_LINUX_DEFAULT="console=tty1 console=ttyS0"

# Set the grub console type
GRUB_TERMINAL=console
EOF

# Apply grub configuration
update-grub

echo "=== [setup_cleanup.sh] Complete ==="
