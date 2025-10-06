#!/bin/bash
# File: feature_install_base_setup.sh
# Description: Performs initial VM setup, including NFS client installation and mounting.

set -e

UTILS_PATH=$(dirname "$0")/phoenix_hypervisor_common_utils.sh
if [ -f "$UTILS_PATH" ]; then
    source "$UTILS_PATH"
else
    echo "Error: Common utilities script not found at $UTILS_PATH." >&2
    exit 1
fi

log_info "Starting base setup feature installation..."

# Install NFS client
log_info "Installing nfs-common..."
if ! apt-get update || ! apt-get install -y nfs-common; then
    log_fatal "Failed to install nfs-common."
fi
log_info "nfs-common installed successfully."

# Mount Persistent Storage
CONTEXT_FILE="$(dirname "$0")/vm_context.json"
if [ ! -f "$CONTEXT_FILE" ]; then
    log_fatal "VM context file not found at $CONTEXT_FILE."
fi

log_info "Reading volume information from $CONTEXT_FILE..."
NFS_SERVER=$(jq -r '.volumes[] | select(.type == "nfs") | .server' "$CONTEXT_FILE")
NFS_PATH=$(jq -r '.volumes[] | select(.type == "nfs") | .path' "$CONTEXT_FILE")
MOUNT_POINT=$(jq -r '.volumes[] | select(.type == "nfs") | .mount_point' "$CONTEXT_FILE")

if [ -z "$NFS_SERVER" ] || [ -z "$NFS_PATH" ] || [ -z "$MOUNT_POINT" ]; then
    log_warn "Incomplete or missing NFS volume information in context file. Skipping mount."
else
    log_info "Creating mount point directory: $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"

    fstab_entry="${NFS_SERVER}:${NFS_PATH} ${MOUNT_POINT} nfs defaults,auto,nofail 0 0"
    log_info "Ensuring fstab entry is present: ${fstab_entry}"
    if ! grep -qxF "$fstab_entry" /etc/fstab; then
        echo "$fstab_entry" >> /etc/fstab
    fi

    log_info "Attempting to mount all filesystems..."
    if ! mount -a || ! mount | grep -q "$MOUNT_POINT"; then
        log_fatal "Failed to mount NFS share at ${MOUNT_POINT}. Check NFS server and network configuration."
    fi
    log_info "NFS share mounted successfully."
fi

log_info "Base setup feature installation completed."

# --- Firewall Configuration for Portainer Roles ---
log_info "Checking for Portainer role to configure firewall..."
PORTAINER_ROLE=$(jq -r '.portainer_role // "none"' "$CONTEXT_FILE")

if [ "$PORTAINER_ROLE" != "none" ]; then
    log_info "Portainer role '$PORTAINER_ROLE' detected. Configuring firewall..."
    
    if ! command -v ufw &> /dev/null; then
        log_info "Installing ufw..."
        apt-get install -y ufw
    fi

    if [ "$PORTAINER_ROLE" == "primary" ]; then
        log_info "Allowing incoming traffic on ports 9000 (HTTP) and 9443 (HTTPS) for Portainer server..."
        ufw allow 9000/tcp
        ufw allow 9443/tcp
    elif [ "$PORTAINER_ROLE" == "agent" ]; then
        log_info "Allowing incoming traffic on port 9001 for Portainer agent..."
        ufw allow 9001/tcp
    fi

    log_info "Enabling the firewall..."
    echo "y" | ufw enable
    log_info "Firewall configured."
else
    log_info "No Portainer role. Skipping firewall configuration."
fi
