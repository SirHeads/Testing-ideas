#!/bin/bash

# File: hypervisor_feature_setup_zfs.sh
# File: hypervisor_feature_setup_zfs.sh
# Description: Configures ZFS pools and datasets on a Proxmox VE host, and integrates
#              them as storage within Proxmox. This script reads ZFS configurations
#              from `hypervisor_config.json`, performs drive checks, creates pools
#              and datasets with specified properties, and adds them to Proxmox VE.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq, lsblk, zpool,
#               zfs, smartctl (optional), free, awk, wipefs, pvesm, grep, sed.
# Inputs:
#   Configuration values from HYPERVISOR_CONFIG_FILE: .zfs.pools[] (name, raid_level, disks[]),
#   .zfs.datasets[] (name, pool, mountpoint, properties{}), .zfs.arc_max.
# Outputs:
#   ZFS pool and dataset creation logs, drive wear statistics, Proxmox storage
#   additions, log messages to stdout and MAIN_LOG_FILE, exit codes indicating
#   success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# Source common utilities
source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh # Source common utilities for logging and error handling

# Ensure script is run as root
check_root # Ensure the script is run with root privileges

log_info "Starting ZFS pools, datasets, and Proxmox storage setup."

# --- ZFS Pool Creation Functions (adapted from phoenix_setup_zfs_pools.sh) ---

# check_available_drives: Verifies drive availability and ZFS pool membership
# Args: $1: Full drive path (e.g., /dev/disk/by-id/nvme-...)
# Returns: 0 on success, 1 on failure
# =====================================================================================
# Function: check_available_drives
# Description: Verifies if a given drive path exists and is not already part of a ZFS pool.
#              It also attempts to determine the drive type.
# Arguments:
#   $1 (drive_path) - The full path to the drive (e.g., /dev/disk/by-id/nvme-...).
# Returns:
#   0 on success, exits with a fatal error if the drive does not exist or is
#   already part of a ZFS pool.
# =====================================================================================
check_available_drives() {
    local drive_path="$1" # Path to the drive to check

    # Check if the drive block device exists
    if [ ! -b "$drive_path" ]; then
        log_fatal "Drive $drive_path does not exist"
    fi

    # Check if the drive is already part of an existing ZFS pool
    if zpool status | grep -q "$drive_path"; then
        log_fatal "Drive $drive_path is already part of a ZFS pool"
    fi

    # Attempt to determine the drive type (e.g., "nvme", "sata")
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
# =====================================================================================
# Function: monitor_nvme_wear
# Description: Monitors NVMe drive wear levels using `smartctl` for specified drive paths.
#              It logs wear statistics if `smartctl` is installed and the drive is NVMe.
# Arguments:
#   $@ (drive_paths) - Space-separated list of full drive paths to monitor.
# Returns:
#   0 on success, logs warnings if `smartctl` is not installed.
# =====================================================================================
monitor_nvme_wear() {
    local drive_paths="$@" # All arguments are treated as drive paths

    # Check if smartctl is installed
    if command -v smartctl >/dev/null 2>&1; then
        for drive_path in $drive_paths; do # Iterate through each drive path
            # Check if the drive is an NVMe device
            if lsblk -d -o NAME,TRAN "$drive_path" | tail -n +2 | grep -q "nvme$"; then
                canonical_name=$(basename "$drive_path") # Get the canonical device name
                smartctl -a "/dev/$canonical_name" | grep -E "Wear_Leveling|Media_Wearout" | log_plain_output # Log wear statistics
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
# =====================================================================================
# Function: check_system_ram
# Description: Checks system RAM against the configured ZFS ARC (Adaptive Replacement Cache)
#              maximum limit. It logs a warning if total RAM is less than twice the
#              ARC max, and attempts to set `zfs_arc_max`.
# Arguments:
#   None (uses global HYPERVISOR_CONFIG_FILE).
# Returns:
#   0 on success, exits with a fatal error if `zfs_arc_max` cannot be set.
# =====================================================================================
check_system_ram() {
    local zfs_arc_max=$(jq -r '.zfs.arc_max // "32212254720"' "$HYPERVISOR_CONFIG_FILE") # Retrieve ZFS ARC max from config (default to 30GB)
    local required_ram=$((zfs_arc_max * 2)) # Recommended RAM is twice ARC max
    local total_ram=$(free -b | awk '/Mem:/ {print $2}') # Total system RAM in bytes

    # Warn if system RAM is less than twice the ZFS ARC max
    if [[ $total_ram -lt $required_ram ]]; then
        log_warn "System RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is less than twice ZFS_ARC_MAX ($((zfs_arc_max / 1024 / 1024 / 1024)) GB). This may cause memory issues."
        # Note: In an automated script, this might be a hard exit depending on policy.
    fi
    log_info "Verified system RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is sufficient for ZFS_ARC_MAX"
    echo "$zfs_arc_max" > /sys/module/zfs/parameters/zfs_arc_max || log_fatal "Failed to set zfs_arc_max to $zfs_arc_max" # Attempt to set zfs_arc_max
    log_info "Set zfs_arc_max to $zfs_arc_max bytes"
}

# create_zfs_pools: Creates ZFS pools based on configuration
# =====================================================================================
# Function: create_zfs_pools
# Description: Creates ZFS pools based on definitions in `hypervisor_config.json`.
#              It checks for existing pools, verifies drive availability, wipes
#              drive partitions, and then creates pools with specified RAID levels
#              and properties. It also monitors NVMe wear and checks system RAM.
# Arguments:
#   None (uses global HYPERVISOR_CONFIG_FILE).
# Returns:
#   None. Exits with a fatal error if pool creation or drive operations fail.
# =====================================================================================
create_zfs_pools() {
    log_info "Creating ZFS pools..."
    local pools_config # Variable to store ZFS pools configuration
    pools_config=$(jq -c '.zfs.pools[]' "$HYPERVISOR_CONFIG_FILE") # Retrieve ZFS pools array from config

    # Iterate through each ZFS pool definition
    for pool_json in $pools_config; do
        local pool_name=$(echo "$pool_json" | jq -r '.name') # Pool name
        local raid_level=$(echo "$pool_json" | jq -r '.raid_level') # RAID level (e.g., mirror, RAIDZ1)
        local disks_array=($(echo "$pool_json" | jq -r '.disks[]')) # Array of disks for the pool

        # Skip pool creation if the pool already exists
        if zfs_pool_exists "$pool_name"; then
            log_info "Pool $pool_name already exists, skipping creation."
            continue
        fi

        log_info "Checking drives for pool $pool_name..."
        for drive in "${disks_array[@]}"; do # Check each drive in the pool
            check_available_drives "$drive" # Call function to verify drive availability
        done

        log_info "Wiping partitions on drives for pool $pool_name..."
        for drive in "${disks_array[@]}"; do # Wipe partitions on each drive
            retry_command "wipefs -a $drive" || log_fatal "Failed to wipe partitions on $drive" # Wipe existing file system signatures
            log_info "Wiped partitions on $drive"
        done

        local create_cmd="zpool create -f -o autotrim=on -O compression=lz4 -O atime=off $pool_name" # Base command for zpool create
        # Append RAID level to the command if specified
        if [[ "$raid_level" == "mirror" ]]; then
            create_cmd="$create_cmd mirror"
        elif [[ "$raid_level" == "RAIDZ1" ]]; then
            create_cmd="$create_cmd raidz1"
        fi
        create_cmd="$create_cmd ${disks_array[*]}" # Add disks to the create command

        retry_command "$create_cmd" || log_fatal "Failed to create $pool_name pool" # Execute zpool create command
        log_info "Created ZFS pool $pool_name on ${disks_array[*]}"
    done

    # Monitor NVMe wear for all configured drives
    # Collect all configured drives for NVMe wear monitoring
    local all_drives=()
    while IFS= read -r line; do
        all_drives+=("$line")
    done < <(jq -r '.zfs.pools[].disks[]' "$HYPERVISOR_CONFIG_FILE") # Extract all disk paths from config
    monitor_nvme_wear "${all_drives[@]}" # Call function to monitor NVMe wear

    check_system_ram # Check and configure system RAM for ZFS ARC
}

# --- ZFS Dataset Creation Functions (adapted from phoenix_setup_zfs_datasets.sh) ---

# create_zfs_datasets: Creates ZFS datasets based on configuration
# =====================================================================================
# Function: create_zfs_datasets
# Description: Creates ZFS datasets based on definitions in `hypervisor_config.json`.
#              It checks for existing datasets, verifies the parent pool, and creates
#              or updates datasets with specified mountpoints and properties.
# Arguments:
#   None (uses global HYPERVISOR_CONFIG_FILE).
# Returns:
#   None. Exits with a fatal error if dataset creation or property setting fails.
# =====================================================================================
create_zfs_datasets() {
    log_info "Creating ZFS datasets..."
    local datasets_config # Variable to store ZFS datasets configuration
    datasets_config=$(jq -c '.zfs.datasets[]' "$HYPERVISOR_CONFIG_FILE") # Retrieve ZFS datasets array from config

    # Iterate through each ZFS dataset definition
    for dataset_json in $datasets_config; do
        local dataset_name=$(echo "$dataset_json" | jq -r '.name') # Dataset name
        local pool_name=$(echo "$dataset_json" | jq -r '.pool') # Parent pool name
        local mountpoint=$(echo "$dataset_json" | jq -r '.mountpoint') # Mountpoint for the dataset
        local properties_json=$(echo "$dataset_json" | jq -c '.properties') # JSON object of properties

        local full_dataset_path="$pool_name/$dataset_name" # Full path of the dataset

        # Check if the parent ZFS pool exists
        if ! zfs_pool_exists "$pool_name"; then
            log_fatal "Pool $pool_name for dataset $full_dataset_path does not exist."
        fi

        local zfs_create_props=() # Array to hold ZFS creation properties
        # Convert JSON properties to `-o key=value` format for `zfs create`
        if [[ "$properties_json" != "null" ]]; then
            while IFS='=' read -r key value; do
                zfs_create_props+=("-o" "$key=$value")
            done < <(echo "$properties_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
        fi

        # Create dataset if it doesn't exist, otherwise update its properties
        if ! zfs_dataset_exists "$full_dataset_path"; then
            create_zfs_dataset "$pool_name" "$dataset_name" "$mountpoint" "${zfs_create_props[@]}" || log_fatal "Failed to create ZFS dataset $full_dataset_path"
            log_info "Created ZFS dataset: $full_dataset_path with mountpoint $mountpoint"
        else
            log_info "Dataset $full_dataset_path already exists. Updating properties."
            local properties_array=() # Array to hold ZFS properties for updating
            # Convert JSON properties to `key=value` format for `zfs set`
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
# =====================================================================================
# Function: check_pvesm
# Description: Checks for the availability of the `pvesm` command, which is used
#              for Proxmox storage management.
# Arguments:
#   None.
# Returns:
#   0 on success, exits with a fatal error if `pvesm` is not found.
# =====================================================================================
check_pvesm() {
  # Check if the `pvesm` command exists in the system's PATH
  if ! command -v pvesm >/dev/null 2>&1; then
    log_fatal "pvesm command not found"
  fi
  log_info "Verified pvesm availability"
}

# add_proxmox_storage: Adds Proxmox storage for datasets based on configuration
# =====================================================================================
# Function: add_proxmox_storage
# Description: Adds ZFS datasets as storage to Proxmox VE. It iterates through
#              configured datasets, derives storage IDs, and uses `pvesm add zfspool`
#              to integrate them with Proxmox.
# Arguments:
#   None (uses global HYPERVISOR_CONFIG_FILE).
# Returns:
#   None. Exits with a fatal error if `pvesm add zfspool` fails.
# =====================================================================================
add_proxmox_storage() {
    log_info "Adding Proxmox storage entries..."
    check_pvesm # Ensure pvesm command is available

    local datasets_config # Variable to store ZFS datasets configuration
    datasets_config=$(jq -c '.zfs.datasets[]' "$HYPERVISOR_CONFIG_FILE") # Retrieve ZFS datasets array from config

    # Iterate through each ZFS dataset defined in the configuration
    for dataset_json in $datasets_config; do
        local dataset_name=$(echo "$dataset_json" | jq -r '.name') # Dataset name
        local pool_name=$(echo "$dataset_json" | jq -r '.pool') # Parent pool name
        local mountpoint=$(echo "$dataset_json" | jq -r '.mountpoint') # Mountpoint (not directly used for zfspool type)
        local full_dataset_path="$pool_name/$dataset_name" # Full path of the dataset

        local storage_id="${pool_name}-${dataset_name}" # Derive a unique storage ID for Proxmox

        # Determine storage type and content from config (or default)
        local storage_type="zfspool" # For direct ZFS integration, type is 'zfspool'
        local content_type="images" # Default content type for ZFS storage in Proxmox

        # Check if this storage ID already exists
        # Check if Proxmox storage with this ID already exists
        if pvesm status | grep -q "^$storage_id"; then
            log_info "Proxmox storage $storage_id already exists, skipping creation."
            continue
        fi

        log_info "Processing dataset $full_dataset_path for Proxmox storage (ID: $storage_id, Type: $storage_type, Content: $content_type)"

        case "$storage_type" in
        case "$storage_type" in
            "zfspool")
                retry_command "pvesm add zfspool $storage_id -pool $full_dataset_path -content $content_type" || log_fatal "Failed to add ZFS storage $storage_id" # Add ZFS storage to Proxmox
                log_info "Added Proxmox ZFS storage: $storage_id for $full_dataset_path with content $content_type"
                ;;
            "dir")
                # This case is for directory storage, which is not directly from ZFS pools in this context.
                # For ZFS datasets, we primarily use "zfspool" type. If a dataset needs to be exposed
                # as a "dir" type, it would typically be a separate entry in the configuration.
                log_warn "Skipping 'dir' type storage for ZFS dataset $full_dataset_path. Only 'zfspool' is supported for direct ZFS integration."
                ;;
            *)
                log_warn "Unsupported storage type '$storage_type' for dataset $full_dataset_path. Skipping."
                ;;
        esac
    done
}

# Main execution
# =====================================================================================
# Function: main
# Description: Main execution flow for the ZFS setup script.
#              It orchestrates the creation of ZFS pools and datasets, and their
#              integration as storage within Proxmox VE.
# Arguments:
#   None.
# Returns:
#   Exits with status 0 on successful completion.
# =====================================================================================
main() {
  create_zfs_pools # Create ZFS pools
  create_zfs_datasets # Create ZFS datasets
  add_proxmox_storage # Add ZFS storage to Proxmox
  
  log_info "Successfully completed hypervisor_feature_setup_zfs.sh"
  exit 0
}

main "$@" # Call the main function to execute the script

log_info "Successfully completed hypervisor_feature_setup_zfs.sh"
exit 0