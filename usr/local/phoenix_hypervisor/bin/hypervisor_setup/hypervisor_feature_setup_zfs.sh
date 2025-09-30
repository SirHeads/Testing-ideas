#!/bin/bash

# File: hypervisor_feature_setup_zfs.sh
# Description: This script provides a comprehensive, declarative management layer for ZFS on the Proxmox VE host.
#              It is a cornerstone of the hypervisor setup, responsible for creating and configuring ZFS pools,
#              managing ZFS datasets with specific properties, and integrating them as storage resources within Proxmox.
#              The script reads its entire configuration from a central JSON file, adhering to Infrastructure-as-Code principles.
#              Crucially, it incorporates multiple safety modes ('safe', 'interactive', 'force-destructive') to prevent
#              accidental data loss on existing systems, which is a primary design consideration.
#
# Dependencies:
#   - /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - `jq`: For parsing the JSON configuration file.
#   - `zfs`, `zpool`: The core ZFS command-line tools.
#   - `pvesm`: The Proxmox VE Storage Manager for integrating ZFS pools as storage.
#   - Standard system utilities: `lsblk`, `wipefs`, `awk`, `grep`, `cat`.
#
# Inputs:
#   - --config FILE: Path to the hypervisor configuration JSON file. Can be '-' to read from stdin.
#   - --mode MODE: The execution mode.
#     - `safe` (default): Aborts if any potentially destructive operation is required (e.g., wiping a disk).
#     - `interactive`: Prompts the user for confirmation before performing destructive operations.
#     - `force-destructive`: Proceeds with destructive operations without prompting.
#   - The JSON configuration is expected to contain a `.zfs` object with `pools` and `datasets` arrays.
#
# Outputs:
#   - Creates and configures ZFS pools and datasets.
#   - Adds ZFS pools and datasets as storage resources in Proxmox VE.
#   - Logs all operations, warnings, and errors to standard output.
#   - Exit Code: 0 on success, non-zero on failure.

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# Ensure script is run as root
check_root

log_info "Starting ZFS pools, datasets, and Proxmox storage setup."

# --- Configuration and Execution Mode ---
EXECUTION_MODE="safe" # Default to the safest mode to prevent accidental data loss.

# Parse command-line arguments to override default mode or set config file path.
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
# This allows the script to be flexible, either reading from a file passed by the orchestrator
# or directly from a JSON string piped to it.
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

# Validate the execution mode to ensure it's one of the allowed values.
if [[ "$EXECUTION_MODE" != "safe" && "$EXECUTION_MODE" != "interactive" && "$EXECUTION_MODE" != "force-destructive" ]]; then
    log_fatal "Invalid execution mode: $EXECUTION_MODE. Allowed modes are 'safe', 'interactive', 'force-destructive'."
fi
log_info "Running in '$EXECUTION_MODE' mode."

# =====================================================================================
# Function: check_available_drives
# Description: Verifies that a given disk drive is available for use in a new ZFS pool.
#              It checks for the existence of the block device and ensures it is not
#              already a member of an existing ZFS pool.
# =====================================================================================
check_available_drives() {
    local drive_path="$1"

    if [ ! -b "$drive_path" ]; then
        log_fatal "Drive $drive_path does not exist"
    fi

    if zpool status | grep -q "$drive_path"; then
        log_fatal "Drive $drive_path is already part of a ZFS pool"
    fi

    local DRIVE_TYPE=$(lsblk -d -o NAME,TRAN "$drive_path" | tail -n +2 | awk '{print $2}')
    log_info "Verified that drive $drive_path (type: ${DRIVE_TYPE:-unknown}) is available"
}

# =====================================================================================
# Function: monitor_nvme_wear
# Description: Logs the wear level of NVMe drives using `smartctl`. This is useful for
#              monitoring the health of the underlying storage hardware.
# =====================================================================================
monitor_nvme_wear() {
    if command -v smartctl >/dev/null 2>&1; then
        for drive_path in "$@"; do
            if lsblk -d -o NAME,TRAN "$drive_path" | tail -n +2 | grep -q "nvme"; then
                local smart_output
                smart_output=$(smartctl -a "$drive_path" | grep -E "Wear_Leveling|Media_Wearout" || true)
                if [ -n "$smart_output" ]; then
                    echo "$smart_output" | log_plain_output
                    log_info "NVMe wear stats for $drive_path logged"
                fi
            fi
        done
    else
        log_warn "smartctl not installed, skipping NVMe wear monitoring"
    fi
}

# =====================================================================================
# Function: check_system_ram
# Description: Checks if the system has sufficient RAM for the configured ZFS ARC size
#              and sets the `zfs_arc_max` kernel parameter accordingly.
# =====================================================================================
check_system_ram() {
    local arc_max_gb=$(echo "$config_json" | jq -r '.zfs.arc_max_gb')
    local zfs_arc_max_bytes=$((arc_max_gb * 1024 * 1024 * 1024))
    local required_ram=$((zfs_arc_max_bytes * 2))
    local total_ram=$(free -b | awk '/Mem:/ {print $2}')

    if [[ $total_ram -lt $required_ram ]]; then
        log_warn "System RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is less than twice ZFS_ARC_MAX ($arc_max_gb GB). This may cause memory issues."
    fi
    echo "$zfs_arc_max_bytes" > /sys/module/zfs/parameters/zfs_arc_max || log_fatal "Failed to set zfs_arc_max to $zfs_arc_max_bytes"
    log_info "Set zfs_arc_max to $zfs_arc_max_bytes bytes ($arc_max_gb GB)"
}

# =====================================================================================
# Function: create_zfs_pools
# Description: The main function for creating ZFS pools. It reads the pool definitions
#              from the configuration, performs safety checks, wipes disks (if allowed by
#              the execution mode), and creates the pools with the specified RAID level.
# =====================================================================================
create_zfs_pools() {
    log_info "Processing ZFS pools based on configuration..."

    local allow_destructive=$(echo "$config_json" | jq -r '.zfs.settings.allow_destructive_operations // "false"')
    if [[ "$allow_destructive" == "true" ]]; then
        log_warn "Destructive operations are allowed via configuration file. Overriding mode to 'force-destructive'."
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

        # Idempotency: If the pool already exists, skip creation.
        if zfs_pool_exists "$pool_name"; then
            log_info "Pool '$pool_name' already exists. Skipping creation."
            continue
        fi

        log_info "Pool '$pool_name' does not exist. Proceeding with creation..."
        log_info "Checking drives for pool '$pool_name'..."
        for drive in "${disks_array[@]}"; do
            check_available_drives "$drive"
        done

        # Destructive operation: Wipe disks before creating a new pool.
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
            else # safe mode
                log_fatal "Found existing signatures on $drive. Aborting in safe mode. Use --mode interactive or --mode force-destructive to override."
            fi
            log_info "Wiped partitions on $drive"
        done

        # Construct and execute the zpool create command.
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

# =====================================================================================
# Function: create_zfs_datasets
# Description: Creates ZFS datasets within the previously created pools. It reads dataset
#              definitions from the configuration, including properties like compression
#              and recordsize, and applies them.
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
        local mountpoint="/$full_dataset_path"

        if ! zfs_pool_exists "$pool_name"; then
            log_fatal "Pool $pool_name for dataset $full_dataset_path does not exist."
        fi

        local zfs_create_props=()
        IFS=',' read -r -a props_array <<< "$properties_str"
        for prop in "${props_array[@]}"; do
            zfs_create_props+=("-o" "$prop")
        done

        # Idempotency: If dataset exists, update properties. If not, create it.
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

# =====================================================================================
# Function: check_pvesm
# Description: Checks for the availability of the `pvesm` command.
# =====================================================================================
check_pvesm() {
  if ! command -v pvesm >/dev/null 2>&1; then
    log_fatal "pvesm command not found. This script must be run on a Proxmox VE host."
  fi
  log_info "Verified pvesm availability"
}

# =====================================================================================
# Function: add_proxmox_storage
# Description: Integrates the newly created ZFS datasets as storage resources within
#              Proxmox VE. This makes them available in the Proxmox UI for storing
#              VM disks, ISO images, backups, etc.
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
        local storage_id_key="${pool_name}_${dataset_name//-/_}"
        local mapped_storage_id=$(echo "$config_json" | jq -r --arg key "$storage_id_key" '.proxmox_storage_ids[$key]')
        
        local storage_id=$([ -n "$mapped_storage_id" ] && [ "$mapped_storage_id" != "null" ] && echo "$mapped_storage_id" || echo "${pool_name}-${dataset_name}")
        
        local mountpoint="/$full_dataset_path"

        # Convergent State Logic: Check if storage exists and update if necessary, or create if it doesn't.
        if pvesm status | grep -q "^$storage_id"; then
            local storage_block=$(awk -v id="$storage_id" '$0 ~ "^(dir|zfspool): " id "$" {f=1} f && /^$/ {f=0} f' /etc/pve/storage.cfg)
            if [ -n "$storage_block" ]; then
                local current_type=$(echo "$storage_block" | head -n 1 | awk -F: '{print $1}')
                local current_content=$(echo "$storage_block" | grep '^\s*content' | awk '{print $2}')

                if [ "$current_type" != "$proxmox_storage_type" ]; then
                    log_fatal "Proxmox storage '$storage_id' exists with incorrect type. Current: '$current_type', Desired: '$proxmox_storage_type'. Manual intervention required."
                fi

                if [ "$current_content" != "$proxmox_content_type" ]; then
                    log_info "Proxmox storage '$storage_id' exists but has incorrect content type. Updating..."
                    retry_command "pvesm set $storage_id --content $proxmox_content_type" || log_fatal "Failed to update Proxmox storage '$storage_id'"
                    log_info "Successfully updated content type for storage '$storage_id'."
                else
                    log_info "Proxmox storage '$storage_id' already exists and is correctly configured."
                fi
            else
                log_warn "Could not retrieve config for existing storage '$storage_id'. Assuming correct."
            fi
        else
            log_info "Proxmox storage '$storage_id' does not exist. Creating..."
            if [[ "$proxmox_storage_type" == "zfspool" ]]; then
                retry_command "pvesm add zfspool $storage_id -pool $full_dataset_path -content $proxmox_content_type" || log_fatal "Failed to add ZFS storage '$storage_id'"
                log_info "Added Proxmox ZFS storage: '$storage_id' for '$full_dataset_path'"
            elif [[ "$proxmox_storage_type" == "dir" ]]; then
                mkdir -p "$mountpoint" || log_fatal "Failed to create directory '$mountpoint'"
                retry_command "pvesm add dir $storage_id -path $mountpoint -content $proxmox_content_type -shared 1" || log_fatal "Failed to add directory storage '$storage_id'"
                log_info "Added Proxmox directory storage: '$storage_id' for path '$mountpoint'"
            else
                log_warn "Unsupported proxmox_storage_type '$proxmox_storage_type' for dataset '$full_dataset_path'. Skipping."
            fi
        fi
    done <<< "$zfs_datasets_json"
}

# =====================================================================================
# Function: main
# Description: Main execution flow for the ZFS setup script. It orchestrates the
#              creation of ZFS pools, datasets, and their integration with Proxmox VE.
# =====================================================================================
main() {
    create_zfs_pools
    create_zfs_datasets
    add_proxmox_storage
    
    log_info "Successfully completed hypervisor_feature_setup_zfs.sh"
    exit 0
}

main "$@"