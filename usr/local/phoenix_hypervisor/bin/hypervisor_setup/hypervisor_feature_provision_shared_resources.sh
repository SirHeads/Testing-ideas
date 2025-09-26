#!/bin/bash
#
# File: hypervisor_feature_provision_shared_resources.sh
# Description: Idempotently creates shared ZFS volumes as hypervisor-level resources.
#

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# Ensure script is run as root
check_root

# Get the configuration file path from the first argument
if [ -z "$1" ]; then
    log_fatal "Configuration file path not provided."
fi
HYPERVISOR_CONFIG_FILE="$1"

# =====================================================================================
# Function: provision_shared_zfs_volumes
# Description: Idempotently creates shared ZFS volumes as hypervisor-level resources.
# =====================================================================================
provision_shared_zfs_volumes() {
    log_info "Provisioning shared ZFS volumes..."
    local shared_volumes
    shared_volumes=$(jq -c '.shared_zfs_volumes // {}' "$HYPERVISOR_CONFIG_FILE")

    for volume_name in $(echo "$shared_volumes" | jq -r 'keys[]'); do
        local volume_config
        volume_config=$(echo "$shared_volumes" | jq -r --arg name "$volume_name" '.[$name]')
        local storage_pool
        storage_pool=$(echo "$volume_config" | jq -r '.pool')
        local size_gb
        size_gb=$(echo "$volume_config" | jq -r '.size_gb')
        # Use a placeholder CTID like 99999 for hypervisor-level resources
        local placeholder_ctid="99999"
        local volume_id="vm-${placeholder_ctid}-disk-${volume_name}"

        # Check if the volume already exists
        if ! pvesm list "$storage_pool" | grep -q "$volume_id"; then
            log_info "Creating shared ZFS volume: $volume_id of size ${size_gb}G in pool $storage_pool"
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
    exit_script 0
}

main
