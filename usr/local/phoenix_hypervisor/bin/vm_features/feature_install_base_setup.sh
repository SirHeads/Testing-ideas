#!/bin/bash
# File: feature_install_base_setup.sh
# Description: Performs initial VM setup, including NFS client installation and mounting.

set -e
export PHOENIX_DEBUG="true" # Temporarily force debug mode for this script

UTILS_PATH=$(dirname "$0")/phoenix_hypervisor_common_utils.sh
if [ -f "$UTILS_PATH" ]; then
    source "$UTILS_PATH"
else
    echo "Error: Common utilities script not found at $UTILS_PATH." >&2
    exit 1
fi

# Enable verbose logging if PHOENIX_DEBUG is set to "true"
if [ "$PHOENIX_DEBUG" == "true" ]; then
    set -x
fi

log_info "Starting base setup feature installation..."

# nfs-common is installed as part of the template creation via virt-customize.
# This script handles the mounting of the persistent storage volume.

# Mount Persistent Storage
CONTEXT_FILE="$(dirname "$0")/vm_context.json"
if [ ! -f "$CONTEXT_FILE" ]; then
    log_fatal "VM context file not found at $CONTEXT_FILE."
fi

log_info "Step 2: NFS mounts are now handled by the vm-manager. Skipping redundant setup."
log_info "Base setup feature installation completed."

# --- Disable IPv6 ---
log_info "Step 3: Disabling IPv6 to ensure proper DNS resolution..."
cat <<EOF > /etc/sysctl.d/99-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl -p
log_info "Step 3: IPv6 disabled."

# --- Disable Internal Firewall (ufw) ---
log_info "Step 4: Disabling internal firewall (ufw) to rely on Proxmox VE firewall..."
if command -v ufw &> /dev/null; then
    log_info "ufw is present, disabling it now."
    ufw disable || log_warn "Failed to disable ufw, but continuing."
    systemctl stop ufw || log_warn "Failed to stop ufw service, but continuing."
    systemctl disable ufw || log_warn "Failed to disable ufw service, but continuing."
    log_info "ufw has been disabled and stopped."
else
    log_info "ufw not found, skipping."
fi
