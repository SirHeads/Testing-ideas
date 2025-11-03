#!/bin/bash

# File: provision_cloud_template.sh
# Description: This script automates the creation of a master Proxmox VM template from an official Ubuntu Cloud Image.
#              It serves as the foundational "one-time" provisioning step for the entire VM templating workflow.
#              The script is idempotent; it checks if the target VMID already exists and exits gracefully if it does.
#              The process includes downloading the cloud image, customizing it by injecting the `qemu-guest-agent`
#              for better host-guest communication, creating a new VM, importing the disk, configuring the hardware,
#              and finally, converting the VM into a template that can be rapidly cloned for new VM deployments.
#
# Dependencies:
#   - /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - `qm`: The Proxmox QEMU/KVM command-line tool.
#   - `wget`: For downloading the cloud image.
#   - `libguestfs-tools`: Provides the `virt-customize` utility for modifying the cloud image offline.
#
# Inputs:
#   - --vmid <VMID>: (Required) The unique numeric ID to assign to the new VM template.
#   - --storage-pool <pool>: (Required) The name of the Proxmox storage pool where the template's disk will be created.
#   - --bridge <bridge>: (Required) The name of the Proxmox network bridge for the template's network interface.
#
# Outputs:
#   - A new Proxmox VM template, ready for cloning.
#   - Logs all operations to a timestamped log file in `/var/log/phoenix_hypervisor/`.
#   - Exit Code: 0 on success, non-zero on failure.

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
# Description: Parses and validates the required command-line arguments.
# =====================================================================================
parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --vmid) VMID="$2"; shift 2 ;;
            --storage-pool) STORAGE_POOL="$2"; shift 2 ;;
            --bridge) NETWORK_BRIDGE="$2"; shift 2 ;;
            *) log_fatal "Unknown option: $1" ;;
        esac
    done

    if [ -z "$VMID" ] || [ -z "$STORAGE_POOL" ] || [ -z "$NETWORK_BRIDGE" ]; then
        log_fatal "Usage: $0 --vmid <VMID> --storage-pool <pool> --bridge <bridge>"
    fi
}

# =====================================================================================
# Function: main
# Description: The main entry point for the script. Orchestrates the entire template
#              provisioning process from argument parsing to final cleanup.
# =====================================================================================
main() {
    setup_logging "/var/log/phoenix_hypervisor/provision_template_$(date +%Y%m%d).log"
    parse_arguments "$@"

    log_info "Starting cloud image template provisioning for VMID: $VMID"

    # --- Idempotency Check ---
    # If a VM with the specified ID already exists, we assume the template has been
    # created previously and exit cleanly.
    if qm config "$VMID" &> /dev/null; then
        log_info "VM $VMID already exists. Assuming it is the correct template. Exiting."
        exit_script 0
    fi

    # --- Install Dependencies ---
    # `libguestfs-tools` is required for `virt-customize`.
    if ! dpkg -l | grep -q "libguestfs-tools"; then
        log_info "Installing libguestfs-tools..."
        apt-get update
        apt-get install -y libguestfs-tools
    fi

    # --- Download Image ---
    # Download the official Ubuntu cloud image if it doesn't already exist locally.
    if [ ! -f "$DOWNLOAD_PATH" ]; then
        log_info "Downloading Ubuntu cloud image from $IMAGE_URL..."
        if ! wget -O "$DOWNLOAD_PATH" "$IMAGE_URL"; then
            log_fatal "Failed to download cloud image."
        fi
    else
        log_info "Cloud image already downloaded."
    fi

    # --- Customize Image ---
    # This is a critical step. `virt-customize` allows us to modify the image offline
    # before it's ever booted. We inject the `qemu-guest-agent`, which is essential
    # for the Proxmox host to communicate reliably with the guest VM.
    log_info "Installing qemu-guest-agent and nfs-common into the cloud image..."
    if ! virt-customize -a "$DOWNLOAD_PATH" --install qemu-guest-agent,nfs-common --run-command 'systemctl enable qemu-guest-agent'; then
        log_fatal "Failed to customize cloud image."
    fi

    # --- Create and Configure VM ---
    # Create a new VM with a base configuration. Serial console is configured for debugging.
    log_info "Creating VM $VMID..."
    qm create "$VMID" --name "ubuntu-2404-cloud-template" --memory 2048 --net0 "virtio,bridge=${NETWORK_BRIDGE}" --scsihw virtio-scsi-pci --serial0 socket --vga serial0

    # Import the customized cloud image as the primary disk for the new VM.
    log_info "Importing downloaded disk to ${STORAGE_POOL}..."
    qm set "$VMID" --scsi0 "${STORAGE_POOL}:0,import-from=${DOWNLOAD_PATH}"

    # Attach a Cloud-Init drive, which Proxmox will use to pass configuration data to the VM on first boot.
    log_info "Configuring Cloud-Init drive..."
    qm set "$VMID" --ide2 "${STORAGE_POOL}:cloudinit"

    # Set the boot order to prioritize the primary disk.
    log_info "Setting boot order..."
    qm set "$VMID" --boot order=scsi0

    # --- Convert to Template ---
    # This command marks the VM as a template, preventing it from being started directly
    # and making it available for cloning.
    log_info "Converting VM $VMID to a template..."
    qm template "$VMID"

    # --- Cleanup ---
    # Remove the downloaded image file to save space.
    log_info "Cleaning up downloaded image file..."
    rm -f "$DOWNLOAD_PATH"

    log_info "Template provisioning for VMID $VMID completed successfully."
}

main "$@"