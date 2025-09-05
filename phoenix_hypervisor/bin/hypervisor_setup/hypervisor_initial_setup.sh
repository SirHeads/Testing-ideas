#!/bin/bash

# File: hypervisor_initial_setup.sh
# Description: Initializes the Proxmox VE environment with essential configurations,
#              including repositories, system updates, timezone, NTP, network settings,
#              and firewall rules for the Phoenix server.
# Version: 1.0.0
# Author: Roo (AI Architect)

# Source common utilities
source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh

# Ensure script is run as root
check_root

log_info "Starting initial Proxmox VE setup."

# Configure log rotation
log_info "Configuring log rotation for $MAIN_LOG_FILE..."
cat << EOF > /etc/logrotate.d/phoenix_hypervisor
$MAIN_LOG_FILE {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
log_info "Configured log rotation for $MAIN_LOG_FILE"

# --- BEGIN MODIFIED REPOSITORY CONFIGURATION (FOR PROXMOX 9 - TRIXIE) ---
log_info "Configuring Proxmox repositories for Trixie..."

# Disable Enterprise Repositories (check for both .list and .sources)
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    mv /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.list.bak
    log_info "Backed up Proxmox VE subscription repository file (.list)"
elif [ -f /etc/apt/sources.list.d/pve-enterprise.sources ]; then
    mv /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/pve-enterprise.sources.bak
    log_info "Backed up Proxmox VE subscription repository file (.sources)"
else
    log_warn "Proxmox VE subscription repository file (.list or .sources) not found, skipping backup"
fi

if [ -f /etc/apt/sources.list.d/ceph.list ]; then
    mv /etc/apt/sources.list.d/ceph.list /etc/apt/sources.list.d/ceph.list.bak
    log_info "Backed up Ceph subscription repository file (.list)"
elif [ -f /etc/apt/sources.list.d/ceph.sources ]; then
    mv /etc/apt/sources.list.d/ceph.sources /etc/apt/sources.list.d/ceph.sources.bak
    log_info "Backed up Ceph subscription repository file (.sources)"
else
    log_warn "Ceph subscription repository file (.list or .sources) not found, skipping backup"
fi

# Enable No-Subscription Repositories (using trixie and ceph-squid)
if ! grep -q "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" /etc/apt/sources.list; then
    echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" >> /etc/apt/sources.list
    log_info "Added Proxmox VE no-subscription repository for trixie"
else
    log_warn "Proxmox VE no-subscription repository for trixie already enabled, skipping"
fi

if ! grep -q "deb http://download.proxmox.com/debian/ceph-squid trixie no-subscription" /etc/apt/sources.list; then
    echo "deb http://download.proxmox.com/debian/ceph-squid trixie no-subscription" >> /etc/apt/sources.list
    log_info "Added Ceph no-subscription repository (ceph-squid) for trixie"
else
    log_warn "Ceph no-subscription repository (ceph-squid) for trixie already enabled, skipping"
fi
log_info "Proxmox repositories configured."
# --- END MODIFIED REPOSITORY CONFIGURATION ---

# Update and upgrade system
log_info "Updating and upgrading system (this may take a while)..."
retry_command "apt-get update" || log_fatal "Failed to update package lists"
retry_command "apt-get dist-upgrade -y" || log_fatal "Failed to upgrade system"
retry_command "proxmox-boot-tool refresh" || log_fatal "Failed to refresh proxmox-boot-tool"
retry_command "update-initramfs -u" || log_fatal "Failed to update initramfs"
log_info "System updated, upgraded, and initramfs refreshed"

# Install jq
log_info "Installing jq..."
retry_command "apt-get install -y jq" || log_fatal "Failed to install jq"
log_info "Installed jq"

# Install s-tui
log_info "Installing s-tui..."
retry_command "apt-get install -y s-tui" || log_fatal "Failed to install s-tui"
log_info "Installed s-tui"

# Install Samba packages
if ! command -v smbd >/dev/null 2>&1; then
    log_info "Installing Samba..."
    retry_command "apt-get install -y samba samba-common-bin smbclient" || log_fatal "Failed to install Samba"
    log_info "Installed Samba"
else
    log_info "Samba already installed, skipping installation"
fi

# Set timezone
log_info "Setting timezone to America/New_York..."
retry_command "timedatectl set-timezone America/New_York" || log_fatal "Failed to set timezone"
log_info "Timezone set to America/New_York"

# Configure NTP
log_info "Configuring NTP with chrony..."
retry_command "apt-get install -y chrony" || log_fatal "Failed to install chrony"
retry_command "systemctl enable --now chrony.service" || log_fatal "Failed to enable chrony"
log_info "NTP configured with chrony"

# Read network configuration from hypervisor_config.json
log_info "Reading network configuration from $HYPERVISOR_CONFIG_FILE..."
HOSTNAME=$(jq -r '.network.hostname // "phoenix"' "$HYPERVISOR_CONFIG_FILE")
INTERFACE=$(jq -r '.network.interfaces.name // "vmbr0"' "$HYPERVISOR_CONFIG_FILE")
IP_ADDRESS=$(jq -r '.network.interfaces.address // "10.0.0.13/24"' "$HYPERVISOR_CONFIG_FILE")
GATEWAY=$(jq -r '.network.interfaces.gateway // "10.0.0.1"' "$HYPERVISOR_CONFIG_FILE")
DNS_SERVER=$(jq -r '.network.interfaces.dns_nameservers // "8.8.8.8"' "$HYPERVISOR_CONFIG_FILE")

if [[ -z "$HOSTNAME" || -z "$INTERFACE" || -z "$IP_ADDRESS" || -z "$GATEWAY" || -z "$DNS_SERVER" ]]; then
    log_fatal "Missing network configuration in $HYPERVISOR_CONFIG_FILE. Please ensure hostname, interface, address, gateway, and dns_nameservers are defined."
fi

log_info "Using network configuration: Hostname=$HOSTNAME, Interface=$INTERFACE, IP=$IP_ADDRESS, Gateway=$GATEWAY, DNS=$DNS_SERVER"

# Set hostname
retry_command "hostnamectl set-hostname $HOSTNAME" || log_fatal "Failed to set hostname"
log_info "Set hostname to $HOSTNAME"

# Configure network
log_info "Configuring static IP for interface $INTERFACE..."
cat << EOF > /etc/network/interfaces.d/50-$INTERFACE.cfg
auto $INTERFACE
iface $INTERFACE inet static
    address $IP_ADDRESS
    gateway $GATEWAY
    dns-nameservers $DNS_SERVER
EOF
retry_command "systemctl restart networking" || log_fatal "Failed to restart networking"
log_info "Configured static IP for interface $INTERFACE with address $IP_ADDRESS, gateway $GATEWAY, and DNS $DNS_SERVER"

# Update /etc/hosts
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
    log_info "Added $HOSTNAME to /etc/hosts"
else
    log_info "Hostname $HOSTNAME already in /etc/hosts, skipping"
fi

# Install ufw if not present
if ! command -v ufw >/dev/null 2>&1; then
    log_info "Installing ufw..."
    retry_command "apt-get install -y ufw" || log_fatal "Failed to install ufw"
    log_info "Installed ufw"
fi

# Configure firewall
log_info "Configuring firewall rules..."
retry_command "ufw allow OpenSSH" || log_fatal "Failed to allow OpenSSH in firewall"
retry_command "ufw allow 8006/tcp" || log_fatal "Failed to allow Proxmox UI port in firewall"
retry_command "ufw allow 2049/tcp" || log_fatal "Failed to allow NFS port in firewall"
retry_command "ufw allow 111/tcp" || log_fatal "Failed to allow RPC port in firewall"
retry_command "ufw allow Samba" || log_fatal "Failed to allow Samba in firewall"
retry_command "ufw enable" || log_fatal "Failed to enable ufw"
log_info "Firewall rules configured and enabled"

log_info "Successfully completed hypervisor_initial_setup.sh"

exit 0