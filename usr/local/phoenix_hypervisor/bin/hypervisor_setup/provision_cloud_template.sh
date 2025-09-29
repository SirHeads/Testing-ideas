#!/bin/bash
#
# File: provision_cloud_template.sh
# Description: Provisions a Proxmox VM template from an Ubuntu Cloud Image.
# This script is designed to be idempotent and can be run safely multiple times.
#
# Inputs:
#   --vmid <VMID>: (Required) The VMID for the new template.
#   --storage-pool <pool>: (Required) The storage pool to import the disk to.
#   --bridge <bridge>: (Required) The network bridge for the VM.
#
# Version: 1.0.0
# Author: Roo

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
VMID=""
STORAGE_POOL=""
NETWORK_BRIDGE=""
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_NAME=$(basename "$IMAGE_URL")
DOWNLOAD_PATH="/tmp/${IMAGE_NAME}"

# =====================================================================================
# Function: parse_arguments
# =====================================================================================
parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --vmid)
                VMID="$2"
                shift 2
                ;;
            --storage-pool)
                STORAGE_POOL="$2"
                shift 2
                ;;
            --bridge)
                NETWORK_BRIDGE="$2"
                shift 2
                ;;
            *)
                log_fatal "Unknown option: $1"
                ;;
        esac
    done

    if [ -z "$VMID" ] || [ -z "$STORAGE_POOL" ] || [ -z "$NETWORK_BRIDGE" ]; then
        log_fatal "Usage: $0 --vmid <VMID> --storage-pool <pool> --bridge <bridge>"
    fi
}

# =====================================================================================
# Function: main
# =====================================================================================
main() {
    setup_logging "/var/log/phoenix_hypervisor/provision_template_$(date +%Y%m%d).log"
    parse_arguments "$@"

    log_info "Starting cloud image template provisioning for VMID: $VMID"

    # --- Idempotency Check ---
    if qm config "$VMID" &> /dev/null; then
        log_info "VM $VMID already exists. Assuming it is the correct template. Exiting."
        exit_script 0
    fi

    # --- Install Dependencies ---
    if ! dpkg -l | grep -q "libguestfs-tools"; then
        log_info "Installing libguestfs-tools..."
        apt-get update
        apt-get install -y libguestfs-tools
    fi

    # --- Download Image ---
    if [ ! -f "$DOWNLOAD_PATH" ]; then
        log_info "Downloading Ubuntu cloud image from $IMAGE_URL..."
        if ! wget -O "$DOWNLOAD_PATH" "$IMAGE_URL"; then
            log_fatal "Failed to download cloud image."
        fi
    else
        log_info "Cloud image already downloaded."
    fi

    # --- Customize Image ---
    log_info "Installing qemu-guest-agent into the cloud image..."
    if ! virt-customize -a "$DOWNLOAD_PATH" --install qemu-guest-agent --run-command 'systemctl enable qemu-guest-agent'; then
        log_fatal "Failed to customize cloud image."
    fi

    # --- Create and Configure VM ---
    log_info "Creating VM $VMID..."
    qm create "$VMID" --name "ubuntu-2404-cloud-template" --memory 2048 --net0 "virtio,bridge=${NETWORK_BRIDGE}" --scsihw virtio-scsi-pci --serial0 socket --vga serial0

    log_info "Importing downloaded disk to ${STORAGE_POOL}..."
    qm set "$VMID" --scsi0 "${STORAGE_POOL}:0,import-from=${DOWNLOAD_PATH}"

    log_info "Configuring Cloud-Init drive..."
    qm set "$VMID" --ide2 "${STORAGE_POOL}:cloudinit"

    log_info "Setting boot order..."
    qm set "$VMID" --boot order=scsi0

    # --- Convert to Template ---
    log_info "Converting VM $VMID to a template..."
    qm template "$VMID"

    # --- Cleanup ---
    log_info "Cleaning up downloaded image file..."
    rm -f "$DOWNLOAD_PATH"

    log_info "Template provisioning for VMID $VMID completed successfully."
}

main "$@"