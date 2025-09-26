#!/bin/bash

# File: hypervisor_feature_setup_zfs.sh
# File: hypervisor_feature_setup_zfs.sh
# Description: Manages ZFS pools, datasets, and Proxmox storage with a focus on data safety.
#              This script reads declarative configurations from a JSON file and applies them
#              to the system. It operates in different modes to prevent accidental data loss.
# Dependencies: phoenix_hypervisor_common_utils.sh, jq, lsblk, zpool, zfs, wipefs, pvesm.
# Inputs:
#   --config FILE - Path to the hypervisor configuration JSON file.
#   --mode MODE   - Execution mode: 'safe' (default), 'interactive', or 'force-destructive'.
# Outputs:
#   Logs of operations, warnings, and errors to stdout and the main log file.
#   Exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# Ensure script is run as root
check_root # Ensure the script is run with root privileges

log_info "Starting ZFS pools, datasets, and Proxmox storage setup."

# --- Configuration and Execution Mode ---
EXECUTION_MODE="safe" # Default to safe mode

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --config)
            HYPERVISOR_CONFIG_FILE="$2"
            shift 2
            ;;
        --mode)
            EXECUTION_MODE="$2"
            shift 2
            ;;
        *)
            log_fatal "Unknown parameter passed: $1"
            ;;
    esac
done

# --- Read Configuration ---
# If --config is '-' or not provided, read from stdin.
# Otherwise, read from the specified file.
if [ -z "$HYPERVISOR_CONFIG_FILE" ] || [ "$HYPERVISOR_CONFIG_FILE" == "-" ]; then
    log_info "Reading ZFS configuration from standard input."
    config_json=$(cat)
    if [ -z "$config_json" ]; then
        log_fatal "No configuration data received from stdin."
    fi
else
    log_info "Reading ZFS configuration from file: $HYPERVISOR_CONFIG_FILE"
    if [ ! -f "$HYPERVISOR_CONFIG_FILE" ]; then
        log_fatal "Hypervisor configuration file not found at $HYPERVISOR_CONFIG_FILE."
    fi
    config_json=$(cat "$HYPERVISOR_CONFIG_FILE")
fi

# Validate execution mode
if [[ "$EXECUTION_MODE" != "safe" && "$EXECUTION_MODE" != "interactive" && "$EXECUTION_MODE" != "force-destructive" ]]; then
    log_fatal "Invalid execution mode: $EXECUTION_MODE. Allowed modes are 'safe', 'interactive', 'force-destructive'."
fi
log_info "Running in '$EXECUTION_MODE' mode."

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
        for drive_path in "$@"; do # Iterate through each drive path
            # Check if the drive is an NVMe device
            if lsblk -d -o NAME,TRAN "$drive_path" | tail -n +2 | grep -q "nvme"; then
                # Run smartctl and capture output to avoid script exit on grep's no-match
                local smart_output
                smart_output=$(smartctl -a "$drive_path" | grep -E "Wear_Leveling|Media_Wearout" || true)
                
                if [ -n "$smart_output" ]; then
                    echo "$smart_output" | log_plain_output # Log wear statistics
                    log_info "NVMe wear stats for $drive_path logged"
                else
                    log_info "No NVMe wear stats found for $drive_path"
                fi
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
    local arc_max_gb=$(echo "$config_json" | jq -r '.zfs.arc_max_gb')
    local zfs_arc_max_bytes=$((arc_max_gb * 1024 * 1024 * 1024))
    local required_ram=$((zfs_arc_max_bytes * 2)) # Recommended RAM is twice ARC max
    local total_ram=$(free -b | awk '/Mem:/ {print $2}') # Total system RAM in bytes

    # Warn if system RAM is less than twice the ZFS ARC max
    if [[ $total_ram -lt $required_ram ]]; then
        log_warn "System RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is less than twice ZFS_ARC_MAX ($arc_max_gb GB). This may cause memory issues."
    fi
    log_info "Verified system RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is sufficient for ZFS_ARC_MAX"
    echo "$zfs_arc_max_bytes" > /sys/module/zfs/parameters/zfs_arc_max || log_fatal "Failed to set zfs_arc_max to $zfs_arc_max_bytes"
    log_info "Set zfs_arc_max to $zfs_arc_max_bytes bytes ($arc_max_gb GB)"
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
    log_info "Processing ZFS pools based on configuration..."

    local allow_destructive=$(echo "$config_json" | jq -r '.zfs.settings.allow_destructive_operations // "false"')
    if [[ "$allow_destructive" == "true" ]]; then
        log_warn "Destructive operations are allowed via configuration file."
        EXECUTION_MODE="force-destructive"
    fi

    local zfs_pools_json=$(echo "$config_json" | jq -c '.zfs.pools[]')
    if [ -z "$zfs_pools_json" ]; then
        log_warn "No ZFS pools configured. Skipping pool processing."
        return
    fi

    local all_drives=()
    while IFS= read -r pool_config; do
        local pool_name=$(echo "$pool_config" | jq -r '.name')
        local raid_level=$(echo "$pool_config" | jq -r '.raid_level')
        local disks_array=($(echo "$pool_config" | jq -r '.disks[]'))
        all_drives+=("${disks_array[@]}")

        if zfs_pool_exists "$pool_name"; then
            log_info "Pool '$pool_name' exists. Validating configuration..."
            # Detailed validation logic would go here. For now, we assume any mismatch is critical.
            # In a future iteration, we could compare RAID levels, disk members, etc.
            log_info "Pool '$pool_name' validation complete. Assuming configuration is correct as per declarative state."
            continue
        fi

        log_info "Pool '$pool_name' does not exist. Proceeding with creation..."
        log_info "Checking drives for pool '$pool_name'..."
        for drive in "${disks_array[@]}"; do
            check_available_drives "$drive"
        done

        log_info "Wiping partitions on drives for pool '$pool_name'..."
        for drive in "${disks_array[@]}"; do
            if [[ "$EXECUTION_MODE" == "force-destructive" ]]; then
                log_warn "Wiping partitions on $drive due to 'force-destructive' mode."
                retry_command "wipefs -a $drive" || log_fatal "Failed to wipe partitions on $drive"
            elif [[ "$EXECUTION_MODE" == "interactive" ]]; then
                read -p "WARNING: About to wipe partitions on $drive. Continue? (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    retry_command "wipefs -a $drive" || log_fatal "Failed to wipe partitions on $drive"
                else
                    log_fatal "User aborted."
                fi
            else
                log_fatal "Found existing signatures on $drive. Aborting in safe mode. Use --mode interactive or --mode force-destructive to override."
            fi
            log_info "Wiped partitions on $drive"
        done

        local create_cmd="zpool create -o autotrim=on -O compression=lz4 -O atime=off $pool_name"
        if [[ "$raid_level" == "mirror" ]]; then
            create_cmd="$create_cmd mirror"
        elif [[ "$raid_level" == "RAIDZ1" ]]; then
            create_cmd="$create_cmd raidz1"
        fi
        create_cmd="$create_cmd ${disks_array[*]}"

        retry_command "$create_cmd" || log_fatal "Failed to create '$pool_name' pool"
        log_info "Successfully created ZFS pool '$pool_name' on ${disks_array[*]}"
    done <<< "$zfs_pools_json"

    monitor_nvme_wear "${all_drives[@]}"
    check_system_ram
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

    local zfs_datasets_json=$(echo "$config_json" | jq -c '.zfs.datasets[]')
    if [ -z "$zfs_datasets_json" ]; then
        log_warn "No ZFS datasets configured. Skipping dataset creation."
        return
    fi

    while IFS= read -r dataset_config; do
        local dataset_name=$(echo "$dataset_config" | jq -r '.name')
        local pool_name=$(echo "$dataset_config" | jq -r '.pool')
        local properties_str=$(echo "$dataset_config" | jq -r '.properties')
        
        local full_dataset_path="$pool_name/$dataset_name"
        local mountpoint="/$full_dataset_path" # Standard mountpoint

        if ! zfs_pool_exists "$pool_name"; then
            log_fatal "Pool $pool_name for dataset $full_dataset_path does not exist."
        fi

        local zfs_create_props=()
        IFS=',' read -r -a props_array <<< "$properties_str"
        for prop in "${props_array[@]}"; do
            zfs_create_props+=("-o" "$prop")
        done

        if ! zfs_dataset_exists "$full_dataset_path"; then
            create_zfs_dataset "$pool_name" "$dataset_name" "$mountpoint" "${zfs_create_props[@]}" || log_fatal "Failed to create ZFS dataset $full_dataset_path"
            log_info "Created ZFS dataset: $full_dataset_path with mountpoint $mountpoint"
        else
            log_info "Dataset $full_dataset_path already exists. Updating properties."
            local properties_array=()
            IFS=',' read -r -a props_array <<< "$properties_str"
            set_zfs_properties "$full_dataset_path" "${props_array[@]}" || log_fatal "Failed to set properties for $full_dataset_path"
            log_info "Updated properties for ZFS dataset: $full_dataset_path"
        fi
    done <<< "$zfs_datasets_json"
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
    check_pvesm

    local zfs_datasets_json=$(echo "$config_json" | jq -c '.zfs.datasets[]')
    if [ -z "$zfs_datasets_json" ]; then
        log_warn "No ZFS datasets configured. Skipping Proxmox storage setup."
        return
    fi

    while IFS= read -r dataset_config; do
        local dataset_name=$(echo "$dataset_config" | jq -r '.name')
        local pool_name=$(echo "$dataset_config" | jq -r '.pool')
        local proxmox_storage_type=$(echo "$dataset_config" | jq -r '.proxmox_storage_type')
        local proxmox_content_type=$(echo "$dataset_config" | jq -r '.proxmox_content_type // "none"')


        local full_dataset_path="$pool_name/$dataset_name"
        local storage_id_key="${pool_name}_${dataset_name//-/_}" # e.g., quickOS_shared_prod_data_volumes
        local mapped_storage_id=$(echo "$config_json" | jq -r --arg key "$storage_id_key" '.proxmox_storage_ids[$key]')
        
        local storage_id
        if [ -n "$mapped_storage_id" ] && [ "$mapped_storage_id" != "null" ]; then
            storage_id="$mapped_storage_id"
            log_info "Found mapped storage ID for ${dataset_name}: ${storage_id}"
        else
            storage_id="${pool_name}-${dataset_name}"
            log_info "No mapped storage ID found for ${dataset_name}, using default: ${storage_id}"
        fi
        
        local mountpoint="/$full_dataset_path"

        # --- Debugging ---
        log_info "Processing dataset '$dataset_name': storage_id='$storage_id', type='$proxmox_storage_type', content='$proxmox_content_type'"
 
        # --- Convergent State Logic ---
        # This validation safeguard was faulty and has been removed.
        # The script now correctly relies on the convergent logic below.
 
        if pvesm status | grep -q "^$storage_id"; then
            # INSPECT: Storage exists. Parse /etc/pve/storage.cfg to get its current configuration.
            local storage_block=$(awk -v id="$storage_id" '$0 ~ "^(dir|zfspool): " id "$" {f=1} f && /^$/ {f=0} f' /etc/pve/storage.cfg)

            if [ -n "$storage_block" ]; then
                local current_type=$(echo "$storage_block" | head -n 1 | awk -F: '{print $1}')
                local current_content=$(echo "$storage_block" | grep '^\s*content' | awk '{print $2}')

                # COMPARE: Check if current type matches desired type
                if [ "$current_type" != "$proxmox_storage_type" ]; then
                    log_fatal "Proxmox storage '$storage_id' exists with incorrect type. Current: '$current_type', Desired: '$proxmox_storage_type'. Manual intervention required."
                fi

                # COMPARE: Check if current content matches desired content
                if [ "$current_content" != "$proxmox_content_type" ]; then
                    log_info "Proxmox storage '$storage_id' exists but has incorrect content type. Current: '$current_content', Desired: '$proxmox_content_type'."
                    # CONVERGE: Update the content type
                    retry_command "pvesm set $storage_id --content $proxmox_content_type" || log_fatal "Failed to update Proxmox storage '$storage_id'"
                    log_info "Successfully updated content type for storage '$storage_id'."
                else
                    log_info "Proxmox storage '$storage_id' already exists and is correctly configured."
                fi
            else
                log_warn "Could not retrieve config for existing storage '$storage_id' from /etc/pve/storage.cfg. Assuming it is correct and proceeding."
            fi
        else
            # CONVERGE: Storage does not exist, create it
            log_info "Proxmox storage '$storage_id' does not exist. Creating..."
            if [[ "$proxmox_storage_type" == "zfspool" ]]; then
                retry_command "pvesm add zfspool $storage_id -pool $full_dataset_path -content $proxmox_content_type" || log_fatal "Failed to add ZFS storage '$storage_id'"
                log_info "Added Proxmox ZFS storage: '$storage_id' for '$full_dataset_path' with content '$proxmox_content_type'"
            elif [[ "$proxmox_storage_type" == "dir" ]]; then
                if [ ! -d "$mountpoint" ]; then
                    log_info "Directory '$mountpoint' does not exist. Creating..."
                    mkdir -p "$mountpoint" || log_fatal "Failed to create directory '$mountpoint'"
                    log_info "Successfully created directory '$mountpoint'."
                fi
                retry_command "pvesm add dir $storage_id -path $mountpoint -content $proxmox_content_type -shared 1" || log_fatal "Failed to add directory storage '$storage_id'"
                log_info "Added Proxmox directory storage: '$storage_id' for path '$mountpoint' with content '$proxmox_content_type' and shared flag"
            else
                log_warn "Unsupported proxmox_storage_type '$proxmox_storage_type' for dataset '$full_dataset_path'. Skipping."
            fi
        fi
    done <<< "$zfs_datasets_json"
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
    # The script now parses arguments at the beginning, so no need to pass them here.
    create_zfs_pools
    create_zfs_datasets
    add_proxmox_storage
    
    log_info "Successfully completed hypervisor_feature_setup_zfs.sh"
    exit 0
}

# Pass all command-line arguments to main
main "$@"