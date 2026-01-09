#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

# =====================================
# ========== UBICLOUD EXTRAS ==========
# =====================================
# To be able to run this image in Ubicloud, we need to remove some Azure specific configurations
# Note: Since we're starting from Ubuntu cloud images (not Azure images), some of these may not exist

sleep 30

# Disable Hyper-V Key Value Pair daemon if it exists
# It blocks booting the VM if it's not disabled
systemctl disable hv-kvp-daemon.service 2>/dev/null || true

# Delete the Azure Linux Agent if it exists
apt -y purge walinuxagent 2>/dev/null || true
rm -rf /var/lib/waagent 2>/dev/null || true
rm -f /var/log/waagent.log 2>/dev/null || true

# Clean up cloud-init logs and cache to run it again on first boot
cloud-init clean --logs --seed

# Delete Azure specific cloud-init config files if they exist
rm -f /etc/cloud/cloud.cfg.d/90-azure.cfg
rm -f /etc/cloud/cloud.cfg.d/10-azure-kvp.cfg

# Replace cloud-init datasource_list with default list
cat > /etc/cloud/cloud.cfg.d/90_dpkg.cfg <<'EOF'
# to update this file, run dpkg-reconfigure cloud-init
datasource_list: [ NoCloud, ConfigDrive, OpenNebula, DigitalOcean, Azure, AltCloud, OVF, MAAS, GCE, OpenStack, CloudSigma, SmartOS, Bigstep, Scaleway, AliYun, Ec2, CloudStack, Hetzner, IBMCloud, Oracle, Exoscale, RbxCloud, UpCloud, VMware, Vultr, LXD, NWCS, None ]
EOF

# Delete Azure specific grub config files if they exist
rm -f /etc/default/grub.d/40-force-partuuid.cfg
rm -f /etc/default/grub.d/50-cloudimg-settings.cfg

# Replace 50-cloudimg-settings with default grub settings
mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/50-cloudimg-settings.cfg <<'EOF'
# Cloud Image specific Grub settings for Generic Cloud Images
# CLOUD_IMG: This file was created/modified by the Cloud Image build process

# Set the recordfail timeout
GRUB_RECORDFAIL_TIMEOUT=0

# Do not wait on grub prompt
GRUB_TIMEOUT=0

# Set the default commandline
GRUB_CMDLINE_LINUX_DEFAULT="console=tty1 console=ttyS0"

# Set the grub console type
GRUB_TERMINAL=console
EOF

# Update grub
update-grub
