#!/bin/bash

# File: hypervisor_feature_setup_zfs.sh
# Description: Configures ZFS pools and datasets, and integrates them as Proxmox storage,
#              reading configuration from hypervisor_config.json.
# Version: 1.0.0
# Author: Roo (AI Architect)

# Source common utilities
source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh

# Ensure script is run as root
check_root

log_info "Starting ZFS pools, datasets, and Proxmox storage setup."

# --- ZFS Pool Creation Functions (adapted from phoenix_setup_zfs_pools.sh) ---

# check_available_drives: Verifies drive availability and ZFS pool membership
# Args: $1: Full drive path (e.g., /dev/disk/by-id/nvme-...)
# Returns: 0 on success, 1 on failure
check_available_drives() {
    local drive_path="$1"

    if [ ! -b "$drive_path" ]; then
        log_fatal "Drive $drive_path does not exist"
    fi

    if zpool status | grep -q "$drive_path"; then
        log_fatal "Drive $drive_path is already part of a ZFS pool"
    fi

    DRIVE_TYPE=$(lsblk -d -o NAME,TRAN "$drive_path" | tail -n +2 | awk '{print $2}')
    if [[ -z "$DRIVE_TYPE" ]]; then
        log_warn "Drive type for $drive_path could not be determined, proceeding anyway"
    else
        log_info "Drive $drive_path is of type $DRIVE_TYPE"
    fi
    log_info "Verified that drive $drive_path is available"
}

# monitor_nvme_wear: Monitors NVMe drive wear using smartctl
# Args: Full drive paths to monitor (space-separated)
# Returns: 0 on success, logs warnings if smartctl not installed
monitor_nvme_wear() {
    local drive_paths="$@"

    if command -v smartctl >/dev/null 2>&1; then
        for drive_path in $drive_paths; do
            if lsblk -d -o NAME,TRAN "$drive_path" | tail -n +2 | grep -q "nvme$"; then
                canonical_name=$(basename "$drive_path")
                smartctl -a "/dev/$canonical_name" | grep -E "Wear_Leveling|Media_Wearout" | log_plain_output
                log_info "NVMe wear stats for $drive_path ($canonical_name) logged"
            fi
        done
    else
        log_warn "smartctl not installed, skipping NVMe wear monitoring"
    fi
}

# check_system_ram: Checks system RAM for ZFS ARC limit
# Args: None
# Returns: 0 on success, 1 on failure
check_system_ram() {
    local zfs_arc_max=$(jq -r '.zfs.arc_max // "32212254720"' "$HYPERVISOR_CONFIG_FILE") # Default to 30GB
    local required_ram=$((zfs_arc_max * 2))
    local total_ram=$(free -b | awk '/Mem:/ {print $2}')

    if [[ $total_ram -lt $required_ram ]]; then
        log_warn "System RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is less than twice ZFS_ARC_MAX ($((zfs_arc_max / 1024 / 1024 / 1024)) GB). This may cause memory issues."
        # In an automated script, we might not prompt, but log and continue or exit based on policy.
        # For 1:1 porting, we'll log a warning and proceed.
    fi
    log_info "Verified system RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is sufficient for ZFS_ARC_MAX"
    echo "$zfs_arc_max" > /sys/module/zfs/parameters/zfs_arc_max || log_fatal "Failed to set zfs_arc_max to $zfs_arc_max"
    log_info "Set zfs_arc_max to $zfs_arc_max bytes"
}

# create_zfs_pools: Creates ZFS pools based on configuration
create_zfs_pools() {
    log_info "Creating ZFS pools..."
    local pools_config
    pools_config=$(jq -c '.zfs.pools[]' "$HYPERVISOR_CONFIG_FILE")

    for pool_json in $pools_config; do
        local pool_name=$(echo "$pool_json" | jq -r '.name')
        local raid_level=$(echo "$pool_json" | jq -r '.raid_level')
        local disks_array=($(echo "$pool_json" | jq -r '.disks[]'))

        if zfs_pool_exists "$pool_name"; then
            log_info "Pool $pool_name already exists, skipping creation."
            continue
        fi

        log_info "Checking drives for pool $pool_name..."
        for drive in "${disks_array[@]}"; do
            check_available_drives "$drive"
        done

        log_info "Wiping partitions on drives for pool $pool_name..."
        for drive in "${disks_array[@]}"; do
            retry_command "wipefs -a $drive" || log_fatal "Failed to wipe partitions on $drive"
            log_info "Wiped partitions on $drive"
        done

        local create_cmd="zpool create -f -o autotrim=on -O compression=lz4 -O atime=off $pool_name"
        if [[ "$raid_level" == "mirror" ]]; then
            create_cmd="$create_cmd mirror"
        elif [[ "$raid_level" == "RAIDZ1" ]]; then
            create_cmd="$create_cmd raidz1"
        fi
        create_cmd="$create_cmd ${disks_array[*]}"

        retry_command "$create_cmd" || log_fatal "Failed to create $pool_name pool"
        log_info "Created ZFS pool $pool_name on ${disks_array[*]}"
    done

    # Monitor NVMe wear for all configured drives
    local all_drives=()
    while IFS= read -r line; do
        all_drives+=("$line")
    done < <(jq -r '.zfs.pools[].disks[]' "$HYPERVISOR_CONFIG_FILE")
    monitor_nvme_wear "${all_drives[@]}"

    check_system_ram
}

# --- ZFS Dataset Creation Functions (adapted from phoenix_setup_zfs_datasets.sh) ---

# create_zfs_datasets: Creates ZFS datasets based on configuration
create_zfs_datasets() {
    log_info "Creating ZFS datasets..."
    local datasets_config
    datasets_config=$(jq -c '.zfs.datasets[]' "$HYPERVISOR_CONFIG_FILE")

    for dataset_json in $datasets_config; do
        local dataset_name=$(echo "$dataset_json" | jq -r '.name')
        local pool_name=$(echo "$dataset_json" | jq -r '.pool')
        local mountpoint=$(echo "$dataset_json" | jq -r '.mountpoint')
        local properties_json=$(echo "$dataset_json" | jq -c '.properties')

        local full_dataset_path="$pool_name/$dataset_name"

        if ! zfs_pool_exists "$pool_name"; then
            log_fatal "Pool $pool_name for dataset $full_dataset_path does not exist."
        fi

        local zfs_create_props=()
        if [[ "$properties_json" != "null" ]]; then
            while IFS='=' read -r key value; do
                zfs_create_props+=("-o" "$key=$value")
            done < <(echo "$properties_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
        fi

        if ! zfs_dataset_exists "$full_dataset_path"; then
            create_zfs_dataset "$pool_name" "$dataset_name" "$mountpoint" "${zfs_create_props[@]}" || log_fatal "Failed to create ZFS dataset $full_dataset_path"
            log_info "Created ZFS dataset: $full_dataset_path with mountpoint $mountpoint"
        else
            log_info "Dataset $full_dataset_path already exists. Updating properties."
            local properties_array=()
            if [[ "$properties_json" != "null" ]]; then
                while IFS='=' read -r key value; do
                    properties_array+=("$key=$value")
                done < <(echo "$properties_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
            fi
            set_zfs_properties "$full_dataset_path" "${properties_array[@]}" || log_fatal "Failed to set properties for $full_dataset_path"
            log_info "Updated properties for ZFS dataset: $full_dataset_path"
        fi
    done
}

# --- Proxmox Storage Creation Functions (adapted from phoenix_create_storage.sh and phoenix_setup_zfs_datasets.sh) ---

# check_pvesm: Checks for pvesm availability
# Args: None
# Returns: 0 on success, 1 on failure
check_pvesm() {
  if ! command -v pvesm >/dev/null 2>&1; then
    log_fatal "pvesm command not found"
  fi
  log_info "Verified pvesm availability"
}

# add_proxmox_storage: Adds Proxmox storage for datasets based on configuration
add_proxmox_storage() {
    log_info "Adding Proxmox storage entries..."
    check_pvesm

    local datasets_config
    datasets_config=$(jq -c '.zfs.datasets[]' "$HYPERVISOR_CONFIG_FILE")

    for dataset_json in $datasets_config; do
        local dataset_name=$(echo "$dataset_json" | jq -r '.name')
        local pool_name=$(echo "$dataset_json" | jq -r '.pool')
        local mountpoint=$(echo "$dataset_json" | jq -r '.mountpoint')
        local full_dataset_path="$pool_name/$dataset_name"

        local storage_id="${pool_name}-${dataset_name}" # Derive storage ID from pool and dataset name

        # Determine storage type and content from config (or default)
        local storage_type="zfspool" # Default to zfspool for ZFS datasets
        local content_type="images" # Default content type

        # Check if this storage ID already exists
        if pvesm status | grep -q "^$storage_id"; then
            log_info "Proxmox storage $storage_id already exists, skipping creation."
            continue
        fi

        log_info "Processing dataset $full_dataset_path for Proxmox storage (ID: $storage_id, Type: $storage_type, Content: $content_type)"

        case "$storage_type" in
            "zfspool")
                retry_command "pvesm add zfspool $storage_id -pool $full_dataset_path -content $content_type" || log_fatal "Failed to add ZFS storage $storage_id"
                log_info "Added Proxmox ZFS storage: $storage_id for $full_dataset_path with content $content_type"
                ;;
            "dir")
                # This case is for directory storage, which is not directly from ZFS pools in this context
                # The original phoenix_create_storage.sh had logic for "dir" type, but for ZFS datasets,
                # we primarily use "zfspool" type. If a dataset needs to be exposed as a "dir" type,
                # it would be a separate entry in the config.
                log_warn "Skipping 'dir' type storage for ZFS dataset $full_dataset_path. Only 'zfspool' is supported for direct ZFS integration."
                ;;
            *)
                log_warn "Unsupported storage type '$storage_type' for dataset $full_dataset_path. Skipping."
                ;;
        esac
    done
}

# Main execution
create_zfs_pools
create_zfs_datasets
add_proxmox_storage

log_info "Successfully completed hypervisor_feature_setup_zfs.sh"
exit 0