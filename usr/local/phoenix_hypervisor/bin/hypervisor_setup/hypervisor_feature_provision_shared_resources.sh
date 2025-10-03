#!/bin/bash

# File: hypervisor_feature_provision_shared_resources.sh
# Description: This script idempotently creates shared ZFS volumes that serve as hypervisor-level resources.
#              It reads its configuration from the `shared_zfs_volumes` section of the main JSON configuration file,
#              adhering to the declarative infrastructure principles of the Phoenix Hypervisor project. These volumes
#              are intended to be shared across multiple guest environments (LXC containers or VMs) but are not
#              tied to any single guest's lifecycle. The script uses the Proxmox VE Storage Manager (`pvesm`)
#              to allocate the volumes within the specified ZFS storage pool.
#
# Dependencies:
#   - /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - `jq`: For parsing the JSON configuration file.
#   - `pvesm`: The Proxmox VE Storage Manager command-line tool.
#
# Inputs:
#   - A path to a JSON configuration file (e.g., `phoenix_hypervisor_config.json`) passed as the first command-line argument.
#   - The JSON file is expected to contain a `.shared_zfs_volumes` object, where each key is a volume name and the value
#     is an object containing:
#       - `pool`: The name of the ZFS storage pool where the volume will be created.
#       - `size_gb`: The size of the volume in gigabytes.
#
# Outputs:
#   - Creates ZFS volumes on the specified storage pool.
#   - Logs its progress to standard output.
#   - Exit Code: 0 on success, non-zero on failure.

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# Ensure script is run as root, as it manages storage resources.
check_root

# Get the configuration file path from the first argument.
if [ -z "$1" ]; then
    log_fatal "Configuration file path not provided."
fi
HYPERVISOR_CONFIG_FILE="$1"

# =====================================================================================
# Function: provision_shared_zfs_volumes
# Description: Reads the `shared_zfs_volumes` configuration and iterates through each
#              defined volume. It performs an idempotency check to see if the volume
#              already exists before attempting to create it using `pvesm alloc`.
# Arguments:
#   None. Uses the global HYPERVISOR_CONFIG_FILE variable.
# Returns:
#   None. The script will exit with a fatal error if volume creation fails.
# =====================================================================================
provision_shared_zfs_volumes() {
    log_info "Provisioning shared ZFS volumes..."
    local shared_volumes
    # Extract the entire shared_zfs_volumes object from the JSON config.
    shared_volumes=$(jq -c '.shared_zfs_volumes // {}' "$HYPERVISOR_CONFIG_FILE")

    # Iterate over each key (volume name) in the shared_volumes object.
    for volume_name in $(echo "$shared_volumes" | jq -r 'keys[]'); do
        local volume_config
        volume_config=$(echo "$shared_volumes" | jq -r --arg name "$volume_name" '.[$name]')
        local storage_pool
        storage_pool=$(echo "$volume_config" | jq -r '.pool')
        local size_gb
        size_gb=$(echo "$volume_config" | jq -r '.size_gb')
        
        # Use a high, reserved placeholder CTID to signify that this is a hypervisor-level resource,
        # not associated with a specific guest VM or container.
        local placeholder_ctid="99999"
        local volume_id="vm-${placeholder_ctid}-disk-${volume_name}"

        # Idempotency Check: Verify if a volume with the generated ID already exists in the target storage pool.
        if ! pvesm list "$storage_pool" | grep -q "$volume_id"; then
            log_info "Creating shared ZFS volume: $volume_id of size ${size_gb}G in pool $storage_pool"
            # Allocate the raw ZFS volume using the Proxmox storage manager.
            if ! pvesm alloc "$storage_pool" "$placeholder_ctid" "$volume_id" "${size_gb}G" --format raw; then
                log_fatal "Failed to create shared ZFS volume: $volume_id"
            fi
        else
            log_info "Shared ZFS volume $volume_id already exists."
        fi
    done
}

# =====================================================================================
# Function: main
# Description: Main entry point for the script.
# =====================================================================================
main() {
    provision_shared_zfs_volumes

    log_info "Creating shared directories..."
    mkdir -p /mnt/pve/quickOS/shared-prod-data/ssl
    mkdir -p /mnt/pve/quickOS/shared-prod-data/logs/nginx
    log_info "Shared directories created successfully."

    exit_script 0
}

main
