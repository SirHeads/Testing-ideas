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

# Install NFS client
log_info "Step 1: Installing nfs-common..."
if ! apt-get update || ! apt-get install -y nfs-common; then
    log_fatal "Failed to install nfs-common."
fi
log_info "Step 1: nfs-common installed successfully."

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

# --- Firewall Configuration for Portainer Roles ---
log_info "Step 3: Checking for Portainer role to configure firewall..."
PORTAINER_ROLE=$(jq -r '.portainer_role // "none"' "$CONTEXT_FILE")

if [ "$PORTAINER_ROLE" != "none" ]; then
    log_info "Step 3: Portainer role '$PORTAINER_ROLE' detected. Configuring firewall..."
    
    if ! command -v ufw &> /dev/null; then
        log_info "Step 3: Installing ufw..."
        apt-get install -y ufw
    fi

    if [ "$PORTAINER_ROLE" == "primary" ]; then
        log_info "Step 3: Allowing incoming traffic on ports 9000 (HTTP) and 9443 (HTTPS) for Portainer server..."
        ufw allow 9000/tcp
        ufw allow 9443/tcp
    elif [ "$PORTAINER_ROLE" == "agent" ]; then
        log_info "Step 3: Allowing incoming traffic on port 9001 for Portainer agent..."
        ufw allow 9001/tcp
    fi

    log_info "Step 3: Enabling the firewall..."
    echo "y" | ufw enable
    log_info "Step 3: Firewall configured."
else
    log_info "Step 3: No Portainer role. Skipping firewall configuration."
fi
