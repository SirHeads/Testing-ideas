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

# nfs-common is now installed as part of the template creation.

# Mount Persistent Storage
CONTEXT_FILE="$(dirname "$0")/vm_context.json"
if [ ! -f "$CONTEXT_FILE" ]; then
    log_fatal "VM context file not found at $CONTEXT_FILE."
fi

log_info "Step 2: Reading volume information from $CONTEXT_FILE..."
NFS_SERVER=$(jq -r '.volumes[] | select(.type == "nfs") | .server' "$CONTEXT_FILE")
NFS_PATH=$(jq -r '.volumes[] | select(.type == "nfs") | .path' "$CONTEXT_FILE")
MOUNT_POINT=$(jq -r '.volumes[] | select(.type == "nfs") | .mount_point' "$CONTEXT_FILE")

if [ -z "$NFS_SERVER" ] || [ -z "$NFS_PATH" ] || [ -z "$MOUNT_POINT" ]; then
    log_warn "Step 2: Incomplete or missing NFS volume information in context file. Skipping mount."
else
    log_info "Step 2: Creating mount point directory: $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"

    fstab_entry="${NFS_SERVER}:${NFS_PATH} ${MOUNT_POINT} nfs defaults,auto,nofail 0 0"
    log_info "Step 2: Ensuring fstab entry is present: ${fstab_entry}"
    if ! grep -qxF "$fstab_entry" /etc/fstab; then
        echo "$fstab_entry" >> /etc/fstab
    fi

    log_info "Step 2: Attempting to mount all filesystems..."
    if ! mount -a || ! mount | grep -q "$MOUNT_POINT"; then
        log_fatal "Step 2: Failed to mount NFS share at ${MOUNT_POINT}. Check NFS server and network configuration."
    fi
    log_info "Step 2: NFS share mounted successfully."
fi

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
