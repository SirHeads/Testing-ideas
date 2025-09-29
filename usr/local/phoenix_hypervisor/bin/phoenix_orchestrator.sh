#!/bin/bash
#
# File: phoenix_orchestrator.sh
# Description: Orchestrates the creation, cloning, starting, stopping, and deletion of LXC containers and VMs.
#              This script serves as the single point of entry for container and VM provisioning,
#              hypervisor setup, and applies features and application scripts to containers.
#              It implements a state machine to ensure idempotent and resumable execution.
#              For application scripts, it uses a contextual execution model, copying the script,
#              utils, and configuration into a temporary directory within the container before execution.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq, pct, qm, ajv (for schema validation).
# Inputs:
#   --dry-run: Optional flag to enable dry-run mode.
#   --setup-hypervisor: Flag to enable hypervisor setup mode.
#   --delete <ID>: Flag to delete a VM or LXC container with a specified ID.
#   <ID>: Positional argument for the Container or VM ID for orchestration.
#   Configuration values from VM_CONFIG_FILE and LXC_CONFIG_FILE.
# Outputs:
#   Log messages to stdout and LOG_FILE, pct and qm command outputs, exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID_LIST=()
DRY_RUN=false # Flag for dry-run mode
SETUP_HYPERVISOR=false # Flag for hypervisor setup mode
DELETE_ID="" # ID of the resource to delete
RECONFIGURE=false
LETSGO=false
SMOKE_TEST=false # Flag for smoke test mode
WIPE_DISKS=false # Flag to wipe disks during hypervisor setup
LOG_FILE="/var/log/phoenix_hypervisor/orchestrator_$(date +%Y%m%d).log"
VM_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_vm_configs.json"
VM_CONFIG_SCHEMA_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_vm_configs.schema.json"
LXC_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_lxc_configs.json"




# =====================================================================================
# Function: parse_arguments
# Description: Parses and validates the command-line arguments.
#              It expects a CTID and an optional --dry-run flag.
# Arguments:
#   $@ - The command-line arguments passed to the script.
# =====================================================================================
# =====================================================================================
# Function: parse_arguments
# Description: Parses and validates command-line arguments to determine the
#              orchestration mode (hypervisor setup, VM management, or LXC container
#              orchestration) and extracts relevant IDs/names.
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   None. Exits with status 2 or a fatal error if arguments are invalid or missing.
# =====================================================================================
parse_arguments() {
   # Display usage and exit if no arguments are provided
   if [ "$#" -eq 0 ]; then
       log_error "Usage: $0 <ID>... [--dry-run] | $0 --delete <ID> [--dry-run] | $0 --setup-hypervisor [--dry-run]"
       exit_script 2
   fi

   local operation_mode_set=false # Flag to ensure only one operation mode is set

   while [[ "$#" -gt 0 ]]; do
       case "$1" in
           --dry-run)
               DRY_RUN=true # Enable dry-run mode
               shift
               ;;
           --wipe-disks)
               WIPE_DISKS=true
               shift
               ;;
           --setup-hypervisor)
               SETUP_HYPERVISOR=true # Enable hypervisor setup mode
               operation_mode_set=true
               shift
               ;;
           --delete)
               if [ -z "$2" ] || [[ "$2" == --* ]]; then
                   log_fatal "Missing ID for --delete flag."
               fi
               DELETE_ID="$2"
               operation_mode_set=true
               shift 2
               ;;
           --reconfigure)
               RECONFIGURE=true
               shift
               ;;
           --LetsGo)
               LETSGO=true
               operation_mode_set=true
               shift
               ;;
           --smoke-test)
               SMOKE_TEST=true # Enable smoke test mode
               operation_mode_set=true
               shift
               ;;
           --test)
               TEST_SUITE="$2"
               operation_mode_set=true
               shift 2
               ;;
           --provision-template)
               PROVISION_TEMPLATE=true
               operation_mode_set=true
               shift
               ;;
           -*) # Handle unknown flags
               log_error "Unknown option: $1"
               exit_script 2
               ;;
           *) # Handle positional arguments (CTIDs/VMIDs for orchestration)
               if [ "$operation_mode_set" = true ] && [ "$LETSGO" = false ] && [ -z "$DELETE_ID" ]; then
                   log_fatal "Cannot combine ID with other operation modes."
               fi
               # Append all remaining arguments to the ID list
               while [[ "$#" -gt 0 ]] && ! [[ "$1" =~ ^-- ]]; do
                   CTID_LIST+=("$1")
                   shift
               done
               operation_mode_set=true
               # This allows --dry-run to appear after the IDs
               if [[ "$#" -gt 0 ]]; then
                  continue
               fi
               ;;
       esac
   done

   # If no operation mode was set, display usage and exit
   if [ "$operation_mode_set" = false ]; then
       log_fatal "Missing required arguments. Usage: $0 <ID>... [--dry-run] | $0 --delete <ID> [--dry-run] | $0 --setup-hypervisor [--dry-run]"
   fi

   # Log the determined operation mode and validate specific arguments
   if [ "$SETUP_HYPERVISOR" = true ]; then
       log_info "Hypervisor setup mode enabled."
   elif [ -n "$DELETE_ID" ]; then
       log_info "Delete mode for ID: $DELETE_ID"
   elif [ "$LETSGO" = true ]; then
       log_info "LetsGo mode enabled. Orchestrating all containers based on boot order."
   elif [ "$SMOKE_TEST" = true ]; then
       log_info "Smoke test mode enabled."
   elif [ -n "$TEST_SUITE" ]; then
       log_info "Test mode enabled for suite: $TEST_SUITE"
   else
       if [ ${#CTID_LIST[@]} -eq 0 ]; then
           if [ "$PROVISION_TEMPLATE" = true ] || [ "$SETUP_HYPERVISOR" = true ] || [ -n "$DELETE_ID" ] || [ "$LETSGO" = true ] || [ "$SMOKE_TEST" = true ] || [ -n "$TEST_SUITE" ]; then
               : # Other modes are active, so no ID is needed
           else
               log_fatal "Missing ID for orchestration. Usage: $0 <ID>... [--dry-run]"
           fi
       fi
       log_info "Orchestration mode for IDs: ${CTID_LIST[*]}"
   fi

    # Log if dry-run mode is enabled
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry-run mode enabled."
    fi
}

# =====================================================================================
# Function: validate_inputs
# Description: Validates the script's essential inputs, such as the presence of the
#              LXC config file and the validity of the CTID.
# =====================================================================================
# =====================================================================================
# Function: validate_inputs
# Description: Validates essential inputs for LXC container orchestration, including
#              the presence of the LXC configuration file and the validity of the CTID.
# Arguments:
#   None (uses global LXC_CONFIG_FILE, CTID).
# Returns:
#   None. Exits with a fatal error if inputs are invalid or configuration is missing.
# =====================================================================================
validate_inputs() {
    local CTID="$1"
    log_info "Starting input validation for CTID $CTID..."
    # Check if LXC_CONFIG_FILE environment variable is set
    if [ -z "$LXC_CONFIG_FILE" ]; then
        log_fatal "LXC_CONFIG_FILE environment variable is not set."
    fi
    log_info "LXC_CONFIG_FILE: $LXC_CONFIG_FILE"

    # Check if the LXC configuration file exists and is readable
    if [ ! -f "$LXC_CONFIG_FILE" ]; then
        log_fatal "LXC configuration file not found or not readable at $LXC_CONFIG_FILE."
    fi

    # Validate CTID format (positive integer)
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_fatal "Invalid CTID '$CTID'. Must be a positive integer."
    fi

    # Check if configuration for the given CTID exists in the LXC config file
    if ! jq_get_value "$CTID" ".name" > /dev/null; then
        log_fatal "Configuration for CTID $CTID not found in $LXC_CONFIG_FILE."
    fi
    log_info "Input validation passed."
}




# =====================================================================================
# Function: create_container_from_template
# Description: Creates a new LXC container from a template file using settings
#              from the JSON configuration.
# =====================================================================================
# =====================================================================================
# Function: check_storage_pool_exists
# Description: Checks if a given storage pool exists on the Proxmox server.
# Arguments:
#   $1 - The name of the storage pool to check.
# Returns:
#   None. Exits with a fatal error if the storage pool does not exist.
# =====================================================================================
check_storage_pool_exists() {
    local storage_pool_name="$1"
    log_info "Checking for existence of storage pool: $storage_pool_name"

    # pvesm status output is like:
    # Name              Type     Status           Total            Used       Available        %
    # local             dir      active      101782260         3100132        93490612    3.05%
    # local-lvm         lvmthin  active      698351616       101155594       597196021   14.49%
    if ! pvesm status | awk 'NR>1 {print $1}' | grep -q "^${storage_pool_name}$"; then
        log_fatal "Storage pool '$storage_pool_name' does not exist on the Proxmox server."
    fi
    log_info "Storage pool '$storage_pool_name' found."
}

# =====================================================================================
# Function: create_container_from_template
# Description: Creates a new LXC container from a specified template using parameters
#              retrieved from the JSON configuration file.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if the `pct create` command fails.
# =====================================================================================
create_container_from_template() {
    local CTID="$1"
    log_info "Starting creation of container $CTID from template."

    # --- Retrieve all necessary parameters from the config file ---
    # Retrieve all necessary parameters from the config file using jq
    local hostname=$(jq_get_value "$CTID" ".name")
    local memory_mb=$(jq_get_value "$CTID" ".memory_mb")
    local cores=$(jq_get_value "$CTID" ".cores")
    local template=$(jq_get_value "$CTID" ".template")
    local storage_pool=$(jq_get_value "$CTID" ".storage_pool")
    local storage_size_gb=$(jq_get_value "$CTID" ".storage_size_gb")

    # --- Check for storage pool existence ---
    check_storage_pool_exists "$storage_pool"
    local features=$(jq_get_value "$CTID" ".features | join(\",\")" || echo "") # Features are handled separately
    local mac_address=$(jq_get_value "$CTID" ".mac_address")
    local unprivileged_bool=$(jq_get_value "$CTID" ".unprivileged")
    local unprivileged_val=$([ "$unprivileged_bool" == "true" ] && echo "1" || echo "0") # Convert boolean to 0 or 1

    # --- Check for template existence and download if necessary ---
    local mount_point_base=$(jq -r '.mount_point_base' "$VM_CONFIG_FILE")
    local iso_dataset_path=$(jq -r '.zfs.datasets[] | select(.name == "shared-iso") | .pool + "/" + .name' "$VM_CONFIG_FILE")
    local template_path="${mount_point_base}/${iso_dataset_path}/template/cache/$(basename "$template")"

    if [ ! -f "$template_path" ]; then
        log_info "Template file not found at $template_path. Attempting to download..."
        # Extract the template name from the filename (e.g., ubuntu-24.04-standard)
        local template_filename=$(basename "$template")
        local template_name="$template_filename"
        
         # Determine the storage ID for ISOs from the configuration file
         local storage_id
         storage_id=$(jq -r '.proxmox_storage_ids.fastdata_iso' "$VM_CONFIG_FILE")
         if [ -z "$storage_id" ] || [ "$storage_id" == "null" ]; then
            log_fatal "Could not determine ISO storage ID from configuration file: $VM_CONFIG_FILE"
         fi

        log_info "Downloading template '$template_name' to storage '$storage_id'..."
        if ! pveam download "$storage_id" "$template_name"; then
            log_fatal "Failed to download template '$template_name'."
        fi
        log_info "Template downloaded successfully."
    fi

    # --- Construct network configuration string ---
    # Construct the network configuration string for net0
    local net0_name=$(jq_get_value "$CTID" ".network_config.name")
    local net0_bridge=$(jq_get_value "$CTID" ".network_config.bridge")
    local net0_ip=$(jq_get_value "$CTID" ".network_config.ip")
    local net0_gw=$(jq_get_value "$CTID" ".network_config.gw")
    local net0_string="name=${net0_name},bridge=${net0_bridge},ip=${net0_ip},gw=${net0_gw},hwaddr=${mac_address}" # Assemble network string

    # --- Build the pct create command array ---
    local pct_create_cmd=(
        create "$CTID" "$template"
        --hostname "$hostname"
        --memory "$memory_mb"
        --cores "$cores"
        --storage "$storage_pool"
        --rootfs "${storage_pool}:${storage_size_gb}"
        --net0 "$net0_string"
        # --gw "$net0_gw"
        --unprivileged "$unprivileged_val"
    )

    # Note: The --features flag is reserved for Proxmox's internal use.
    # Custom features (e.g., Docker, Nvidia) are handled by the state machine after container creation.

    # --- Execute the command ---
    # Execute the `pct create` command
    if ! run_pct_command "${pct_create_cmd[@]}"; then
        log_fatal "'pct create' command failed for CTID $CTID."
    fi
    log_info "Container $CTID created from template successfully."
}

# =====================================================================================
# Function: clone_container
# Description: Clones an LXC container from a source container and a specific snapshot.
# =====================================================================================
# =====================================================================================
# Function: clone_container
# Description: Clones an LXC container from a specified source container and snapshot,
#              applying new hostname and storage pool settings.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if pre-flight checks or the `pct clone` command fail.
# =====================================================================================
clone_container() {
    local CTID="$1"
    local source_ctid=$(jq_get_value "$CTID" ".clone_from_ctid") # Retrieve source CTID from config
    log_info "Starting clone of container $CTID from source CTID $source_ctid."

    local source_snapshot_name=$(jq_get_value "$source_ctid" ".template_snapshot_name") # Retrieve snapshot name from source CTID config

    # --- Pre-flight checks for cloning ---
    # Perform pre-flight checks: ensure source container exists and snapshot is present
    if ! pct status "$source_ctid" > /dev/null 2>&1; then
        log_warn "Source container $source_ctid does not exist yet. Will retry."
        return 1
    fi
    if ! pct listsnapshot "$source_ctid" | grep -q "$source_snapshot_name"; then
        log_warn "Snapshot '$source_snapshot_name' not found on source container $source_ctid yet. Will retry."
        return 1
    fi

    local hostname=$(jq_get_value "$CTID" ".name") # New hostname for the cloned container
    local storage_pool=$(jq_get_value "$CTID" ".storage_pool") # Storage pool for the cloned container
 
    # --- Check for storage pool existence ---
    check_storage_pool_exists "$storage_pool"

     # --- Build the pct clone command array ---
    local pct_clone_cmd=(
        clone "$source_ctid" "$CTID"
        --snapname "$source_snapshot_name"
        --hostname "$hostname"
        --storage "$storage_pool"
    )

    # --- Execute the command ---
    # Execute the `pct clone` command
    if ! run_pct_command "${pct_clone_cmd[@]}"; then
        log_fatal "'pct clone' command failed for CTID $CTID."
    fi
    log_info "Container $CTID cloned from $source_ctid successfully."
}


# =====================================================================================
# Function: apply_configurations
# Description: Applies configurations to a newly created or cloned container, such as
#              memory, cores, features, and network settings.
# =====================================================================================
# =====================================================================================
# Function: apply_configurations
# Description: Applies various configurations (memory, cores, features, network) to
#              a newly created or cloned LXC container based on its JSON configuration.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if any `pct set` command fails.
# =====================================================================================
apply_configurations() {
    local CTID="$1"
    log_info "Applying configurations for CTID: $CTID"
    local conf_file="/etc/pve/lxc/${CTID}.conf"

    # --- Retrieve configuration values ---
    # Retrieve configuration values from the JSON config
    local memory_mb=$(jq_get_value "$CTID" ".memory_mb")
    local cores=$(jq_get_value "$CTID" ".cores")
    local features
    features=$(jq_get_value "$CTID" ".features // [] | .[]" || echo "")
    local start_at_boot=$(jq_get_value "$CTID" ".start_at_boot")
    local boot_order=$(jq_get_value "$CTID" ".boot_order")
    local boot_delay=$(jq_get_value "$CTID" ".boot_delay")
    local start_at_boot_val=$([ "$start_at_boot" == "true" ] && echo "1" || echo "0")
 
     # --- Apply core settings ---
     # Apply core settings: memory and CPU cores
    run_pct_command set "$CTID" --memory "$memory_mb" || log_fatal "Failed to set memory."
    run_pct_command set "$CTID" --cores "$cores" || log_fatal "Failed to set cores."
    run_pct_command set "$CTID" --onboot "${start_at_boot_val}" || log_fatal "Failed to set onboot."
    run_pct_command set "$CTID" --startup "order=${boot_order},up=${boot_delay},down=${boot_delay}" || log_fatal "Failed to set startup."
 
    # --- Apply AppArmor Profile ---
    apply_apparmor_profile "$CTID"

    # --- Apply pct options ---
    local pct_options
    pct_options=$(jq_get_value "$CTID" ".pct_options // [] | .[]" || echo "")
    if [ -n "$pct_options" ]; then
        log_info "Applying pct options for CTID $CTID..."
        local features_to_set=()
        for option in $pct_options; do
            features_to_set+=("$option")
        done
        if [ ${#features_to_set[@]} -gt 0 ]; then
            local features_string
            features_string=$(IFS=,; echo "${features_to_set[*]}")
            log_info "Applying features: $features_string"
            run_pct_command set "$CTID" --features "$features_string" || log_fatal "Failed to set pct options: ${features_to_set[*]}"
        fi
    fi

    # --- Apply lxc options ---
    local lxc_options
    lxc_options=$(jq_get_value "$CTID" ".lxc_options // [] | .[]" || echo "")
    if [ -n "$lxc_options" ]; then
        log_info "Applying lxc options for CTID $CTID..."
        local conf_file="/etc/pve/lxc/${CTID}.conf"
        for option in $lxc_options; do
            if [[ "$option" == "lxc.cap.keep="* ]]; then
                local caps_to_keep=$(echo "$option" | cut -d'=' -f2)
                # Remove existing lxc.cap.keep entries to avoid duplicates
                sed -i '/^lxc.cap.keep/d' "$conf_file"
                # Add each capability on a new line
                for cap in $(echo "$caps_to_keep" | tr ',' ' '); do
                    echo "lxc.cap.keep: $cap" >> "$conf_file" || log_fatal "Failed to add capability to $conf_file: $cap"
                done
            elif ! grep -qF "$option" "$conf_file"; then
                echo "$option" >> "$conf_file" || log_fatal "Failed to add lxc option to $conf_file: $option"
            fi
        done
    fi
    # Note: The --features flag here is for Proxmox's internal features.
    # Custom feature scripts are applied in a later state.


    # --- Apply network settings ---
    # Retrieve network configuration values and construct the net0 string
    local net0_name=$(jq_get_value "$CTID" ".network_config.name")
    local net0_bridge=$(jq_get_value "$CTID" ".network_config.bridge")
    local net0_ip=$(jq_get_value "$CTID" ".network_config.ip")
    local net0_gw=$(jq_get_value "$CTID" ".network_config.gw")
    local mac_address=$(jq_get_value "$CTID" ".mac_address")
    local net0_string="name=${net0_name},bridge=${net0_bridge},ip=${net0_ip},gw=${net0_gw},hwaddr=${mac_address}" # Assemble network string

    # Apply network configuration
    run_pct_command set "$CTID" --net0 "$net0_string" || log_fatal "Failed to set network configuration."
    log_info "Configurations applied successfully for CTID $CTID."
}

ensure_container_defined() {
    local CTID="$1"
    log_info "Ensuring container $CTID is defined..."
    if pct status "$CTID" > /dev/null 2>&1; then
        log_info "Container $CTID already exists. Skipping creation."
        return 0
    fi
    log_info "Container $CTID does not exist. Proceeding with creation..."
    local clone_from_ctid
    clone_from_ctid=$(jq_get_value "$CTID" ".clone_from_ctid" || echo "")
    if [ -n "$clone_from_ctid" ]; then
        if ! clone_container "$CTID"; then
            return 1
        fi
    else
        create_container_from_template "$CTID"
    fi
 
        # NEW: Set unprivileged flag immediately after creation if specified in config
        local unprivileged_bool
        unprivileged_bool=$(jq_get_value "$CTID" ".unprivileged")
        if [ "$unprivileged_bool" == "true" ]; then
            # This check is for cloned containers, as create_from_template handles this.
            if ! pct config "$CTID" | grep -q "unprivileged: 1"; then
                 log_info "Setting container $CTID as unprivileged..."
                 run_pct_command set "$CTID" --unprivileged 1 || log_fatal "Failed to set container as unprivileged."
            fi
        fi
}

# =====================================================================================
# Function: apply_zfs_volumes
# Description: Creates and attaches ZFS volumes to a container.
# =====================================================================================
apply_zfs_volumes() {
    local CTID="$1"
    log_info "Applying ZFS volumes for CTID: $CTID..."

    local volumes
    volumes=$(jq_get_value "$CTID" ".zfs_volumes // [] | .[]" || echo "")
    if [ -z "$volumes" ]; then
        log_info "No ZFS volumes to apply for CTID $CTID."
        return 0
    fi

    local volume_index=0
    # Find the next available mount point index
    while pct config "$CTID" | grep -q "mp${volume_index}:"; do
        volume_index=$((volume_index + 1))
    done

    for volume_config in $(echo "$volumes" | jq -c '.'); do
        local volume_name=$(echo "$volume_config" | jq -r '.name')
        local storage_pool=$(echo "$volume_config" | jq -r '.pool')
        local size_gb=$(echo "$volume_config" | jq -r '.size_gb')
        local mount_point=$(echo "$volume_config" | jq -r '.mount_point')
        local volume_id="mp${volume_index}"

        # Check if the volume is already configured
        if pct config "$CTID" | grep -q "${volume_id}:.*,mp=${mount_point}"; then
            log_info "Volume '${volume_name}' (${volume_id}) already exists for CTID $CTID."
        else
            log_info "Creating and attaching volume '${volume_name}' to CTID $CTID..."
            run_pct_command set "$CTID" --"${volume_id}" "${storage_pool}:${size_gb},mp=${mount_point}" || log_fatal "Failed to create volume '${volume_name}'."
        fi
        volume_index=$((volume_index + 1))
    done
}

# =====================================================================================
# Function: apply_dedicated_volumes
# Description: Creates and attaches dedicated storage volumes to a container.
# =====================================================================================
apply_dedicated_volumes() {
    local CTID="$1"
    log_info "Applying dedicated volumes for CTID: $CTID..."

    local volumes
    volumes=$(jq_get_value "$CTID" ".volumes // [] | .[]" || echo "")
    if [ -z "$volumes" ]; then
        log_info "No dedicated volumes to apply for CTID $CTID."
        return 0
    fi

    local volume_index=0
    for volume_config in $(echo "$volumes" | jq -c '.'); do
        local volume_name=$(echo "$volume_config" | jq -r '.name')
        local storage_pool=$(echo "$volume_config" | jq -r '.pool')
        local size_gb=$(echo "$volume_config" | jq -r '.size_gb')
        local mount_point=$(echo "$volume_config" | jq -r '.mount_point')
        local volume_id="mp${volume_index}"

        # Check if the volume is already configured
        if pct config "$CTID" | grep -q "${volume_id}:.*,mp=${mount_point}"; then
            log_info "Volume '${volume_name}' (${volume_id}) already exists for CTID $CTID."
        else
            log_info "Creating and attaching volume '${volume_name}' to CTID $CTID..."
            run_pct_command set "$CTID" --"${volume_id}" "${storage_pool}:${size_gb},mp=${mount_point}" || log_fatal "Failed to create volume '${volume_name}'."
        fi
        volume_index=$((volume_index + 1))
    done
}

# =====================================================================================
# Function: ensure_container_disk_size
# Description: Ensures the container's root disk size matches the configuration.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if the `pct resize` command fails.
# =====================================================================================
ensure_container_disk_size() {
    local CTID="$1"
    log_info "Ensuring correct disk size for CTID: $CTID"
    local storage_size_gb
    storage_size_gb=$(jq_get_value "$CTID" ".storage_size_gb")

    # The pct resize command is idempotent for our purposes.
    # It sets the disk to the specified size.
    run_pct_command resize "$CTID" rootfs "${storage_size_gb}G"
    log_info "Disk size for CTID $CTID set to ${storage_size_gb}G."
}


# =====================================================================================
# Function: start_container
# Description: Starts the container with retry logic to handle transient issues.
# =====================================================================================
# =====================================================================================
# Function: start_container
# Description: Starts the specified LXC container with retry logic to handle
#              potential transient startup issues.
# Arguments:
#   None (uses global CTID).
# Returns:
#   0 on successful container start, exits with a fatal error if the container
#   fails to start after all retries.
# =====================================================================================
start_container() {
    local CTID="$1"
    log_info "Attempting to start container CTID: $CTID..."

    # Check if the container is already running
    if pct status "$CTID" | grep -q "status: running"; then
        log_info "Container $CTID is already running. Skipping start attempt."
        return 0
    fi

    log_info "Container $CTID is not running. Proceeding with start..."
    local attempts=0 # Counter for startup attempts
    local max_attempts=3 # Maximum number of startup attempts
    local interval=5 # Delay between retries in seconds

    # Loop to attempt container startup with retries
    while [ "$attempts" -lt "$max_attempts" ]; do
        if run_pct_command start "$CTID" 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Container $CTID started successfully."
            return 0
        else
            attempts=$((attempts + 1))
            log_error "WARNING: 'pct start' command failed for CTID $CTID (Attempt $attempts/$max_attempts). Check $LOG_FILE for details."
            if [ "$attempts" -lt "$max_attempts" ]; then
                log_info "Retrying in $interval seconds..."
                sleep "$interval" # Wait before retrying
            fi
        fi
    done

    log_fatal "Container $CTID failed to start after $max_attempts attempts."
}


# =====================================================================================
# Function: apply_features
# Description: Applies a series of feature scripts to the container based on its
#              configuration in the JSON file.
# =====================================================================================
# =====================================================================================
# Function: apply_features
# Description: Iterates through and executes a series of feature scripts for the
#              LXC container based on the 'features' array in its JSON configuration.
#              Each feature script is expected to be idempotent.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if a feature script is not found or fails.
# =====================================================================================
apply_features() {
    local CTID="$1"
    log_info "Applying features for CTID: $CTID"
    local features
    features=$(jq_get_value "$CTID" ".features // [] | .[]" || echo "")

    if [ -z "$features" ]; then
        log_info "No features to apply for CTID $CTID."
        return 0
    fi

    log_info "Features to apply for CTID $CTID: $features"

    for feature in $features; do
        local feature_script_path="${PHOENIX_BASE_DIR}/bin/lxc_setup/phoenix_hypervisor_feature_install_${feature}.sh"
        log_info "Executing feature: $feature ($feature_script_path)"

        if [ ! -f "$feature_script_path" ]; then
            log_fatal "Feature script not found at $feature_script_path."
        fi

        if ! (set +e; "$feature_script_path" "$CTID"); then
            log_error "Feature script '$feature' failed for CTID $CTID."
            return 1
        fi
    done

    log_info "All features applied successfully for CTID $CTID."
}

# =====================================================================================
# Function: run_portainer_script
# Description: Executes the Portainer feature script for the container if it is defined
#              in the configuration.
# =====================================================================================
run_portainer_script() {
    local CTID="$1"
    log_info "Checking for Portainer feature for CTID: $CTID"
    local portainer_role
    portainer_role=$(jq_get_value "$CTID" ".portainer_role" || echo "")

    if [ -z "$portainer_role" ] || [ "$portainer_role" == "none" ]; then
        log_info "No Portainer role to apply for CTID $CTID."
        return 0
    fi

    local portainer_script_path="${PHOENIX_BASE_DIR}/bin/lxc_setup/phoenix_hypervisor_feature_install_portainer.sh"
    log_info "Executing Portainer feature script: $portainer_script_path"

    if [ ! -f "$portainer_script_path" ]; then
        log_fatal "Portainer feature script not found at $portainer_script_path."
    fi

    if ! "$portainer_script_path" "$CTID"; then
        log_fatal "Portainer feature script failed for CTID $CTID."
    fi

    log_info "Portainer feature script applied successfully for CTID $CTID."
}


# =====================================================================================
# Function: run_application_script
# Description: Executes a final application script for the container if one is defined
#              in the configuration.
# =====================================================================================
# =====================================================================================
# Function: run_application_script
# Description: Executes a final application-specific script for the LXC container
#              if one is defined in its JSON configuration. The script is executed
#              inside the container using 'pct exec'.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if the application script is not found or fails.
# =====================================================================================
run_application_script() {
    local CTID="$1"
    log_info "Waiting for container to settle before running application script..."
    sleep 10
    log_info "Checking for application script for CTID: $CTID"
    local app_script_name # Variable to store the application script name
    app_script_name=$(jq_get_value "$CTID" ".application_script" || echo "") # Retrieve application script name from config

    # If no application script is defined, log and exit
    if [ -z "$app_script_name" ]; then
        log_info "No application script to run for CTID $CTID."
        return 0
    fi

    local app_script_path="${PHOENIX_BASE_DIR}/bin/${app_script_name}" # Construct full script path
    log_info "Executing application script inside container: $app_script_name ($app_script_path)"

    # Check if the application script exists
    if [ ! -f "$app_script_path" ]; then
        log_fatal "Application script not found at $app_script_path."
    fi

    # --- New Robust Script Execution Model ---
    local temp_dir_in_container="/tmp/phoenix_run"
    local common_utils_source_path="${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"
    local common_utils_dest_path="${temp_dir_in_container}/phoenix_hypervisor_common_utils.sh"
    local app_script_dest_path="${temp_dir_in_container}/${app_script_name}"

    # 1. Create a temporary directory in the container
    log_info "Creating temporary directory in container: $temp_dir_in_container"
    if ! pct exec "$CTID" -- mkdir -p "$temp_dir_in_container"; then
        log_fatal "Failed to create temporary directory in container $CTID."
    fi

    # Verification step
    log_info "Verifying temporary directory creation..."
    if ! pct exec "$CTID" -- test -d "$temp_dir_in_container"; then
        log_fatal "Verification failed: Temporary directory '$temp_dir_in_container' does not exist in container $CTID."
    fi
    log_info "Temporary directory verified successfully."

    # 2. Copy common_utils.sh to the container
    log_info "Copying common utilities to $CTID:$common_utils_dest_path..."
    if ! pct push "$CTID" "$common_utils_source_path" "$common_utils_dest_path"; then
        log_fatal "Failed to copy common_utils.sh to container $CTID."
    fi

    # 3. Copy the application script to the container
    log_info "Copying application script to $CTID:$app_script_dest_path..."
    if ! pct push "$CTID" "$app_script_path" "$app_script_dest_path"; then
        log_fatal "Failed to copy application script to container $CTID."
    fi

    # 3b. Copy http.js if it exists and the app script is for nginx
    if [[ "$app_script_name" == "phoenix_hypervisor_lxc_953.sh" ]]; then
        local http_js_source_path="${PHOENIX_BASE_DIR}/etc/nginx/scripts/http.js"
        local http_js_dest_path="${temp_dir_in_container}/http.js"
        if [ -f "$http_js_source_path" ]; then
            log_info "Copying http.js to $CTID:$http_js_dest_path..."
            if ! pct push "$CTID" "$http_js_source_path" "$http_js_dest_path"; then
                log_fatal "Failed to copy http.js to container $CTID."
            fi
        fi
    fi
    
    # 3c. Copy the vllm_gateway config file if it exists and the app script is for nginx
    if [[ "$app_script_name" == "phoenix_hypervisor_lxc_953.sh" ]]; then
        local vllm_gateway_source_path="${PHOENIX_BASE_DIR}/etc/nginx/sites-available/vllm_gateway"
        local vllm_gateway_dest_path="${temp_dir_in_container}/vllm_gateway"
        if [ -f "$vllm_gateway_source_path" ]; then
            log_info "Copying vllm_gateway to $CTID:$vllm_gateway_dest_path..."
            if ! pct push "$CTID" "$vllm_gateway_source_path" "$vllm_gateway_dest_path"; then
                log_fatal "Failed to copy vllm_gateway to container $CTID."
            fi
        fi
    fi

    # 3d. Copy the LXC config file to the container's temp directory
    local lxc_config_dest_path="${temp_dir_in_container}/phoenix_lxc_configs.json"
    log_info "Copying LXC config to $CTID:$lxc_config_dest_path..."
    if ! pct push "$CTID" "$LXC_CONFIG_FILE" "$lxc_config_dest_path"; then
        log_fatal "Failed to copy LXC config file to container $CTID."
    fi

    # 4. Make the application script executable
    log_info "Making application script executable in container..."
    if ! pct exec "$CTID" -- chmod +x "$app_script_dest_path"; then
        log_fatal "Failed to make application script executable in container $CTID."
    fi

    # 5. Execute the application script
    log_info "Executing application script in container..."
    if ! pct exec "$CTID" -- "$app_script_dest_path" "$CTID"; then
        log_fatal "Application script '$app_script_name' failed for CTID $CTID."
    fi

    # 6. Clean up the temporary directory
    log_info "Cleaning up temporary directory in container..."
    if ! pct exec "$CTID" -- rm -rf "$temp_dir_in_container"; then
        log_warn "Failed to clean up temporary directory in container $CTID."
    fi

    log_info "Application script executed successfully for CTID $CTID."
}

# =====================================================================================
# Function: run_health_check
# Description: Executes a health check command inside the container if defined in the configuration.
# =====================================================================================
run_health_check() {
    local CTID="$1"
    log_info "Checking for health check for CTID: $CTID"
    # --- NVIDIA Health Check ---
    local features
    features=$(jq_get_value "$CTID" ".features // [] | .[]" || echo "")
    if [[ " ${features[*]} " =~ " nvidia " ]]; then
        log_info "NVIDIA feature detected. Running NVIDIA health check..."
        local nvidia_check_script="${PHOENIX_BASE_DIR}/bin/health_checks/check_nvidia.sh"
        if ! "$nvidia_check_script" "$CTID"; then
            log_fatal "NVIDIA health check failed for CTID $CTID."
        fi
    fi

    # --- Generic Health Check ---
    local health_check_command=$(jq_get_value "$CTID" ".health_check.command" || echo "")

    if [ -z "$health_check_command" ]; then
        log_info "No generic health check to run for CTID $CTID."
        return 0
    fi

    log_info "Executing generic health check command inside container: $health_check_command"
    local attempts=0
    local max_attempts=$(jq_get_value "$CTID" ".health_check.retries" || echo "3")
    local interval=$(jq_get_value "$CTID" ".health_check.interval" || echo "5")

    while [ "$attempts" -lt "$max_attempts" ]; do
        if pct exec "$CTID" -- $health_check_command; then
            log_info "Health check passed successfully for CTID $CTID."
            return 0
        else
            attempts=$((attempts + 1))
            log_error "WARNING: Health check command '$health_check_command' failed for CTID $CTID (Attempt $attempts/$max_attempts)."
            if [ "$attempts" -lt "$max_attempts" ]; then
                log_info "Retrying in $interval seconds..."
                sleep "$interval"
            fi
        fi
    done

    log_fatal "Health check failed for CTID $CTID after $max_attempts attempts."
}

# =====================================================================================
# Function: run_post_deployment_validation
# Description: Executes post-deployment validation tests for a container if enabled.
# =====================================================================================
run_post_deployment_validation() {
    local CTID="$1"
    log_info "Checking for post-deployment validation for CTID: $CTID"
    local test_suites
    test_suites=$(jq -r ".lxc_configs.\"$CTID\".tests | keys[]" "$LXC_CONFIG_FILE")

    if [ -z "$test_suites" ]; then
        log_info "No test suites found for CTID $CTID. Skipping post-deployment validation."
        return 0
    fi

    for suite in $test_suites; do
        log_info "Running test suite '$suite' for CTID $CTID..."
        local test_runner_script="${PHOENIX_BASE_DIR}/bin/tests/test_runner.sh"
        if [ ! -x "$test_runner_script" ]; then
            log_info "Making test runner script executable..."
            chmod +x "$test_runner_script"
        fi
        if ! "$test_runner_script" "$CTID" "$suite"; then
            log_error "Test suite '$suite' failed for CTID $CTID."
            return 1
        fi
    done

    log_info "Post-deployment validation completed successfully for CTID $CTID."
}

# =====================================================================================
# Function: create_template_snapshot
# Description: Creates a snapshot of a container if it is designated as a template
#              in the configuration file.
# =====================================================================================
# =====================================================================================
# Function: create_template_snapshot
# Description: Creates a snapshot of an LXC container if it is designated as a
#              template in the configuration file and the snapshot does not already exist.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if snapshot creation fails.
# =====================================================================================
create_template_snapshot() {
    local CTID="$1"
    log_info "Checking for template snapshot for CTID: $CTID"
    local snapshot_name # Variable to store the template snapshot name
    snapshot_name=$(jq_get_value "$CTID" ".template_snapshot_name" || echo "") # Retrieve snapshot name from config

    # If no template snapshot name is defined, log and exit
    if [ -z "$snapshot_name" ]; then
        log_info "No template snapshot defined for CTID $CTID. Skipping."
        return 0
    fi

    # Check if the snapshot already exists
    if pct listsnapshot "$CTID" | grep -q "$snapshot_name"; then
        log_info "Snapshot '$snapshot_name' already exists for CTID $CTID. Skipping."
        return 0
    fi

    log_info "Creating snapshot '$snapshot_name' for template container $CTID..."
    # Execute the `pct snapshot` command
    local snapshot_output
    if ! snapshot_output=$(run_pct_command snapshot "$CTID" "$snapshot_name" 2>&1); then
        if [[ "$snapshot_output" == *"snapshot feature is not available"* ]]; then
            log_warn "[WARNING] Snapshot feature is not available for CTID $CTID. Skipping snapshot creation."
        else
            log_fatal "Failed to create snapshot '$snapshot_name' for CTID $CTID. Error: $snapshot_output"
        fi
    else
        log_info "Snapshot '$snapshot_name' created successfully."
    fi
}

create_pre_configured_snapshot() {
    local CTID="$1"
    local snapshot_name="pre-configured"
    log_info "Checking for pre-configured snapshot for CTID: $CTID"

    if pct listsnapshot "$CTID" | grep -q "$snapshot_name"; then
        log_info "Snapshot '$snapshot_name' already exists for CTID $CTID. Deleting and recreating."
        if ! run_pct_command delsnapshot "$CTID" "$snapshot_name"; then
            log_fatal "Failed to delete existing snapshot '$snapshot_name' for CTID $CTID."
        fi
    fi

    log_info "Creating snapshot '$snapshot_name' for container $CTID..."
    local snapshot_output
    if ! snapshot_output=$(run_pct_command snapshot "$CTID" "$snapshot_name" 2>&1); then
        if [[ "$snapshot_output" == *"snapshot feature is not available"* ]]; then
            log_warn "[WARNING] Snapshot feature is not available for CTID $CTID. Skipping snapshot creation."
        else
            log_fatal "Failed to create snapshot '$snapshot_name' for CTID $CTID. Error: $snapshot_output"
        fi
    else
        log_info "Snapshot '$snapshot_name' created successfully."
    fi
}

create_final_form_snapshot() {
    local CTID="$1"
    local snapshot_name="final-form"
    log_info "Checking for final-form snapshot for CTID: $CTID"

    if pct listsnapshot "$CTID" | grep -q "$snapshot_name"; then
        log_info "Snapshot '$snapshot_name' already exists for CTID $CTID. Deleting and recreating."
        if ! run_pct_command delsnapshot "$CTID" "$snapshot_name"; then
            log_fatal "Failed to delete existing snapshot '$snapshot_name' for CTID $CTID."
        fi
    fi

    log_info "Creating snapshot '$snapshot_name' for container $CTID..."
    local snapshot_output
    if ! snapshot_output=$(run_pct_command snapshot "$CTID" "$snapshot_name" 2>&1); then
        if [[ "$snapshot_output" == *"snapshot feature is not available"* ]]; then
            log_warn "[WARNING] Snapshot feature is not available for CTID $CTID. Skipping snapshot creation."
        else
            log_fatal "Failed to create snapshot '$snapshot_name' for CTID $CTID. Error: $snapshot_output"
        fi
    else
        log_info "Snapshot '$snapshot_name' created successfully."
    fi
}

# =====================================================================================
# Function: apply_apparmor_profile
# Description: Applies the AppArmor profile to the container's configuration file.
# Arguments:
#   $1 - The CTID of the container.
# =====================================================================================
apply_apparmor_profile() {
    local CTID="$1"
    log_info "Applying AppArmor profile for CTID: $CTID"

    local apparmor_profile
    apparmor_profile=$(jq_get_value "$CTID" ".apparmor_profile" || echo "unconfined")
    local conf_file="/etc/pve/lxc/${CTID}.conf"

    if [ ! -f "$conf_file" ]; then
        log_fatal "Container configuration file not found at $conf_file."
    fi

    log_info "Setting AppArmor profile to: ${apparmor_profile}"
    if [ "$apparmor_profile" == "unconfined" ]; then
        if grep -q "^lxc.apparmor.profile:" "$conf_file"; then
            log_info "Removing existing AppArmor profile setting."
            sed -i '/^lxc.apparmor.profile:/d' "$conf_file"
        fi
    else
        # Load the AppArmor profile
        local custom_profile_path="${PHOENIX_BASE_DIR}/etc/apparmor/${apparmor_profile}"
        local system_profile_path="/etc/apparmor.d/${apparmor_profile}"

        if [ ! -f "$custom_profile_path" ]; then
            log_fatal "Custom AppArmor profile file not found at $custom_profile_path"
        fi

        log_info "Copying custom AppArmor profile to $system_profile_path"
        if ! cp "$custom_profile_path" "$system_profile_path"; then
            log_fatal "Failed to copy AppArmor profile to system directory."
        fi

        local profile_line="lxc.apparmor.profile: ${apparmor_profile}"
        if grep -q "^lxc.apparmor.profile:" "$conf_file"; then
            sed -i "s|^lxc.apparmor.profile:.*|$profile_line|" "$conf_file"
        else
            echo "$profile_line" >> "$conf_file"
        fi

        # Add nesting support if specified
        local apparmor_manages_nesting
        apparmor_manages_nesting=$(jq_get_value "$CTID" ".apparmor_manages_nesting" || echo "false")
        if [ "$apparmor_manages_nesting" = true ]; then
            log_info "Adding nesting support for CTID $CTID"
            echo "lxc.apparmor.allow_nesting: 1" >> "$conf_file" || log_fatal "Failed to add nesting support"
            echo "lxc.include: /usr/share/lxc/config/nesting.conf" >> "$conf_file" || log_fatal "Failed to add nesting config"
        fi
    fi

    # Reload AppArmor profiles to apply changes
    log_info "Reloading AppArmor profiles..."
    systemctl reload apparmor || log_warn "Failed to reload AppArmor profiles."
}

# =====================================================================================
# Function: run_qm_command
# Description: Executes a qm command, logging the command and its output.
# Arguments:
#   $@ - The qm command and its arguments.
# =====================================================================================
# =====================================================================================
# Function: run_qm_command
# Description: Executes a `qm` (Proxmox QEMU/KVM) command, logging the command
#              and handling dry-run mode.
# Arguments:
#   $@ - The `qm` command and its arguments.
# Returns:
#   0 on success, 1 on failure.
# =====================================================================================
run_qm_command() {
    local cmd_description="qm $*" # Description of the command for logging
    log_info "Executing: $cmd_description"
    echo "Executing: $cmd_description"
    # If dry-run mode is enabled, log the command without executing it
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry-run: Skipping actual command execution."
        return 0
    fi
    # Execute the `qm` command
    if ! qm "$@"; then
        log_error "Command failed: $cmd_description"
        return 1
    fi
    return 0
}

# =====================================================================================
# Function: run_pvesm_command
# Description: Executes a pvesm command, logging the command and its output.
# Arguments:
#   $@ - The pvesm command and its arguments.
# =====================================================================================
run_pvesm_command() {
    local cmd_description="pvesm $*"
    log_info "Executing: $cmd_description"
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry-run: Skipping actual command execution."
        return 0
    fi
    if ! pvesm "$@"; then
        log_error "Command failed: $cmd_description"
        return 1
    fi
    return 0
}

# =====================================================================================
# Function: setup_hypervisor
# Description: Orchestrates the setup of the hypervisor by executing a series of scripts.
# Arguments:
#   $1 - The path to the configuration file.
# =====================================================================================
setup_hypervisor() {
    local config_file="$1"
    log_info "Starting hypervisor setup with config file: $config_file"

    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        log_fatal "Hypervisor setup requires a valid configuration file."
    fi

    local zfs_setup_mode="safe"
    if [ "$WIPE_DISKS" = true ]; then
        log_warn "Disk wiping is enabled for this run."
        zfs_setup_mode="force-destructive"
    fi

    local setup_scripts=(
        "hypervisor_initial_setup.sh"
        "hypervisor_feature_setup_zfs.sh"
        "hypervisor_feature_configure_vfio.sh"
        "hypervisor_feature_install_nvidia.sh"
        "hypervisor_feature_initialize_nvidia_gpus.sh"
        "hypervisor_feature_setup_firewall.sh"
        "hypervisor_feature_setup_nfs.sh"
        "hypervisor_feature_create_heads_user.sh"
        "hypervisor_feature_setup_samba.sh"
        "hypervisor_feature_create_admin_user.sh"
        "hypervisor_feature_provision_shared_resources.sh"
        "hypervisor_feature_setup_apparmor.sh"
        "hypervisor_feature_fix_apparmor_tunables.sh"
    )

    for script in "${setup_scripts[@]}"; do
        local script_path="${PHOENIX_BASE_DIR}/bin/hypervisor_setup/${script}"
        log_info "Executing setup script: $script..."
        if [ ! -f "$script_path" ]; then
            log_fatal "Hypervisor setup script not found at $script_path."
        fi
        if [[ "$script" == "hypervisor_feature_setup_zfs.sh" ]]; then
            if ! "$script_path" --config "$config_file" --mode "$zfs_setup_mode"; then
                log_fatal "Hypervisor setup script '$script' failed."
            fi
        elif ! "$script_path" "$config_file"; then
            log_fatal "Hypervisor setup script '$script' failed."
        fi
    done

    log_info "Hypervisor setup completed successfully."
}

# =====================================================================================
# Function: orchestrate_vm
# Description: Main state machine for VM provisioning.
# Arguments:
#   $1 - The VMID of the VM to orchestrate.
# =====================================================================================
orchestrate_vm() {
    local VMID="$1"
    log_info "Starting orchestration for VMID: $VMID"

    # --- VMID Validation ---
    if ! jq -e ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE" > /dev/null; then
        log_fatal "Configuration for VMID $VMID not found in $VM_CONFIG_FILE."
    fi
    log_info "VMID $VMID found in configuration file. Proceeding with orchestration."

    log_info "Available storage pools before VM creation:"
    pvesm status
    ensure_vm_defined "$VMID"
    apply_vm_configurations "$VMID"
    start_vm "$VMID"
    # Wait for the VM to boot and the guest agent to be ready
    wait_for_guest_agent "$VMID"
    apply_vm_features "$VMID"
    create_vm_snapshot "$VMID"

    # --- Template Finalization ---
    local is_template
    is_template=$(jq -r ".vms[] | select(.vmid == $VMID) | .is_template" "$VM_CONFIG_FILE")
    if [ "$is_template" == "true" ]; then
        log_info "Finalizing template for VM $VMID..."
        run_qm_command stop "$VMID"
        run_qm_command start "$VMID"
        wait_for_guest_agent "$VMID"
        log_info "Cleaning cloud-init state for template..."
        run_qm_command guest exec "$VMID" -- /bin/bash -c "cloud-init clean"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "rm -f /etc/machine-id"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "touch /etc/machine-id"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "systemctl stop cloud-init"
        run_qm_command stop "$VMID"
        log_info "Creating final template snapshot..."
        create_vm_snapshot "$VMID"
        log_info "Converting VM to template..."
        run_qm_command template "$VMID"
    fi

    log_info "Available storage pools after VM creation:"
    pvesm status

    log_info "VM orchestration for VMID $VMID completed successfully."
}

# =====================================================================================
# Function: ensure_vm_defined
# Description: Checks if the VM exists. If not, it calls the create_vm function.
# Arguments:
#   $1 - The VMID to check.
# =====================================================================================
ensure_vm_defined() {
    local VMID="$1"
    log_info "Ensuring VM $VMID is defined..."
    if qm status "$VMID" > /dev/null 2>&1; then
        log_info "VM $VMID already exists. Skipping creation."
        return 0
    fi
    log_info "VM $VMID does not exist. Proceeding with creation..."

    local vm_config
    vm_config=$(jq -r ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE")
    local clone_from_vmid
    clone_from_vmid=$(echo "$vm_config" | jq -r '.clone_from_vmid // ""')
    local template_image
    template_image=$(echo "$vm_config" | jq -r '.template_image // ""')

    if [ -n "$clone_from_vmid" ]; then
        clone_vm "$VMID" "$clone_from_vmid"
    elif [ -n "$template_image" ]; then
        create_vm_from_template "$VMID"
    else
        log_fatal "VM definition for $VMID must include either 'clone_from_vmid' or 'template_image'."
    fi
}

# =====================================================================================
# Function: create_vm_from_template
# Description: Creates a new VM from a template image.
# Arguments:
#   $1 - The VMID of the VM to create.
# =====================================================================================
create_vm_from_template() {
    local VMID="$1"
    log_info "Creating VM $VMID from template image."

    local vm_config
    vm_config=$(jq -r "(.vm_defaults) + (.vms[] | select(.vmid == $VMID))" "$VM_CONFIG_FILE")
    local name
    name=$(echo "$vm_config" | jq -r '.name')
    local template_image
    template_image=$(echo "$vm_config" | jq -r '.template_image')
    local storage_pool
    storage_pool=$(echo "$vm_config" | jq -r '.storage_pool')
    local disk_size_gb
    disk_size_gb=$(echo "$vm_config" | jq -r '.disk_size_gb')
    local memory_mb
    memory_mb=$(echo "$vm_config" | jq -r '.memory_mb')
    local cores
    cores=$(echo "$vm_config" | jq -r '.cores')
    local network_bridge
    network_bridge=$(echo "$vm_config" | jq -r '.network_bridge')
    local image_url="https://cloud-images.ubuntu.com/noble/current/${template_image}"
    local download_path="/tmp/${template_image}"

    # --- Download Image ---
    if [ ! -f "$download_path" ]; then
        log_info "Downloading Ubuntu cloud image from $image_url..."
        if ! wget -O "$download_path" "$image_url"; then
            log_fatal "Failed to download cloud image."
        fi
    else
        log_info "Cloud image already downloaded."
    fi

    log_info "Creating new VM $VMID: $name"
    run_qm_command create "$VMID" --name "$name" --memory "$memory_mb" --cores "$cores" --net0 "virtio,bridge=${network_bridge}" --scsihw virtio-scsi-pci --serial0 socket --vga serial0

    log_info "Importing downloaded disk to ${storage_pool}..."
    run_qm_command set "$VMID" --scsi0 "${storage_pool}:0,import-from=${download_path}"

    log_info "Configuring Cloud-Init drive..."
    run_qm_command set "$VMID" --ide2 "${storage_pool}:cloudinit"

    log_info "Setting boot order..."
    run_qm_command set "$VMID" --boot order=scsi0

    log_info "Resizing disk for VM $VMID to ${disk_size_gb}G..."
    run_qm_command resize "$VMID" scsi0 "${disk_size_gb}G"

    log_info "VM $VMID created successfully from template image."
}

# =====================================================================================
# Function: clone_vm
# Description: Clones a new VM from a snapshot of an existing VM.
# Arguments:
#   $1 - The new VMID to create.
#   $2 - The source VMID to clone from.
# =====================================================================================
clone_vm() {
    local new_vmid="$1"
    local source_vmid="$2"
    log_info "Cloning VM $new_vmid from source template VM $source_vmid."

    # --- Pre-flight Checks ---
    if ! qm config "$source_vmid" | grep -q "template: 1"; then
        log_fatal "Source VM $source_vmid is not a template. Cloning is only supported from templates."
    fi

    local new_vm_config
    new_vm_config=$(jq -r "(.vm_defaults) + (.vms[] | select(.vmid == $new_vmid))" "$VM_CONFIG_FILE")
    local new_name
    new_name=$(echo "$new_vm_config" | jq -r '.name')
    local disk_size_gb
    disk_size_gb=$(echo "$new_vm_config" | jq -r '.disk_size_gb')

    # --- Execute Clone ---
    run_qm_command clone "$source_vmid" "$new_vmid" --name "$new_name" --full

    # --- Resize Disk ---
    if [ -n "$disk_size_gb" ]; then
        log_info "Resizing disk for VM $new_vmid to ${disk_size_gb}G..."
        run_qm_command resize "$new_vmid" scsi0 "${disk_size_gb}G"
    fi

    log_info "VM $new_vmid cloned successfully from $source_vmid."
}

# =====================================================================================
# Function: apply_vm_configurations
# Description: Applies configurations to the VM using `qm set`.
# Arguments:
#   $1 - The VMID of the VM to configure.
# =====================================================================================
apply_vm_configurations() {
    local VMID="$1"
    log_info "Applying configurations for VMID: $VMID"

    local vm_config
    vm_config=$(jq -r "(.vm_defaults) + (.vms[] | select(.vmid == $VMID))" "$VM_CONFIG_FILE")
    local name
    name=$(echo "$vm_config" | jq -r '.name')
    local cores
    cores=$(echo "$vm_config" | jq -r '.cores')
    local memory_mb
    memory_mb=$(echo "$vm_config" | jq -r '.memory_mb')
    local network_bridge
    network_bridge=$(echo "$vm_config" | jq -r '.network_bridge')
    
    # Basic hardware settings
    run_qm_command set "$VMID" --cores "$cores" --memory "$memory_mb"
    
    # --- Serial Console for Debugging ---
    log_info "Configuring serial console for debugging..."
    run_qm_command set "$VMID" --serial0 socket --vga serial0
    
    # --- Dynamic Cloud-Init Generation ---
    log_info "Starting Cloud-Init generation for VM $VMID..."
    # --- Secure Cloud-Init Generation ---
    local temp_dir
    temp_dir=$(mktemp -d)
    log_info "Created temporary directory for Cloud-Init files: $temp_dir"
    # Ensure the temporary directory is cleaned up on script exit
    trap 'rm -rf -- "$temp_dir"' EXIT

    local user_template="${PHOENIX_BASE_DIR}/etc/cloud-init/user-data.template.yml"
    local network_template="${PHOENIX_BASE_DIR}/etc/cloud-init/network-config.template.yml"
    local temp_user_data="${temp_dir}/user-data-${VMID}.yml"
    local temp_network_data="${temp_dir}/network-config-${VMID}.yml"
    local snippets_path="/var/lib/vz/snippets"

    # Retrieve dynamic values from JSON
    log_info "Retrieving Cloud-Init values from JSON config..."
    local username
    username=$(echo "$vm_config" | jq -r '.user_config.username')
    local ip_address
    ip_address=$(echo "$vm_config" | jq -r '.network_config.ip')
    local gateway
    gateway=$(echo "$vm_config" | jq -r '.network_config.gw')
    log_info "Successfully retrieved Cloud-Init values."

    # Generate user-data file
    log_info "Generating user-data file from template: $user_template"
    sed -e "s@__HOSTNAME__@${name}@g" \
        -e "s@__USERNAME__@${username}@g" \
        "$user_template" > "$temp_user_data"

    # Embed feature scripts
    local features
    features=$(echo "$vm_config" | jq -r '.features[]? // ""')
    if [ -n "$features" ]; then
        local feature_files_content=""
        for feature in $features; do
            local feature_script_path="${PHOENIX_BASE_DIR}/bin/vm_features/feature_install_${feature}.sh"
            if [ -f "$feature_script_path" ]; then
                local script_content
                script_content=$(cat "$feature_script_path" | sed 's/^/        /')
                feature_files_content+=$(cat <<EOF
  - path: /tmp/features/feature_install_${feature}.sh
    permissions: '0755'
    content: |
${script_content}
EOF
)
            fi
        done
        local temp_feature_files
        temp_feature_files=$(mktemp)
        echo "$feature_files_content" > "$temp_feature_files"
        sed -i -e "/#FEATURE_FILES_PLACEHOLDER#/r ${temp_feature_files}" -e "/#FEATURE_FILES_PLACEHOLDER#/d" "$temp_user_data"
        rm "$temp_feature_files"
    fi

    log_info "Generated user-data file: $temp_user_data"

    # Generate network-config file
    log_info "Generating network-config file from template: $network_template"
    if [ "$ip_address" == "dhcp" ]; then
        sed -e "s/__DHCP4_ENABLED__/true/g" \
            -e "/addresses:/d" \
            -e "/gateway4:/d" \
            "$network_template" > "$temp_network_data"
    else
        sed -e "s/__DHCP4_ENABLED__/false/g" \
            -e "s|__IPV4_ADDRESS__|${ip_address}|g" \
            -e "s|__IPV4_GATEWAY__|${gateway}|g" \
            "$network_template" > "$temp_network_data"
    fi
    log_info "Generated network-config file: $temp_network_data"

    # Copy generated files to snippets directory
    if [ "$DRY_RUN" = false ]; then
        log_info "Creating snippets directory if it doesn't exist: $snippets_path"
        mkdir -p "$snippets_path"
        log_info "Copying generated Cloud-Init files to snippets directory..."
        cp "$temp_user_data" "${snippets_path}/user-data-${VMID}.yml"
        cp "$temp_network_data" "${snippets_path}/network-config-${VMID}.yml"
        log_info "Successfully copied Cloud-Init files."
        rm "$temp_user_data" "$temp_network_data"
    fi

    # Attach Cloud-Init drive
    run_qm_command set "$VMID" --cicustom "user=local:snippets/user-data-${VMID}.yml,network=local:snippets/network-config-${VMID}.yml"

    # Enable QEMU Guest Agent
    run_qm_command set "$VMID" --agent enabled=1

    log_info "VM configurations applied successfully for VMID $VMID."
}

# =====================================================================================
# Function: start_vm
# Description: Starts the VM with retry logic.
# Arguments:
#   $1 - The VMID of the VM to start.
# =====================================================================================
start_vm() {
    local VMID="$1"
    log_info "Attempting to start VM $VMID..."
    if qm status "$VMID" | grep -q "status: running"; then
        log_info "VM $VMID is already running."
        return 0
    fi
    log_info "Executing start command for VM $VMID..."
    if ! run_qm_command start "$VMID"; then
        log_error "Failed to start VM $VMID. Checking journalctl for related errors..."
        journalctl -n 50 --unit pvedaemon --since "1 minute ago"
        log_fatal "VM start command failed. Please review the logs above for details."
    fi
    log_info "VM $VMID start command issued successfully."
}

# =====================================================================================
# Function: wait_for_guest_agent
# Description: Waits for the QEMU Guest Agent to be ready.
# Arguments:
#   $1 - The VMID to check.
# =====================================================================================
wait_for_guest_agent() {
    local VMID="$1"
    log_info "Waiting for QEMU Guest Agent on VM $VMID..."
    local max_attempts=60
    local interval=5
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        log_info "Checking guest agent for VM $VMID, attempt $attempt. Uptime: $(qm guest exec $VMID -- cat /proc/uptime 2>/dev/null || echo 'N/A')"
        if qm agent "$VMID" ping > /dev/null 2>&1; then
            log_info "QEMU Guest Agent is ready."
            return 0
        fi
        sleep $interval
    done
    log_error "Timed out waiting for QEMU Guest Agent on VM $VMID."
    log_info "Attempting to connect to VM console to check for boot issues..."
    if ! qm terminal "$VMID"; then
        log_warn "Could not connect to VM console. The VM may be unresponsive."
    fi
    log_fatal "Guest agent did not become available."
}

# =====================================================================================
# Function: apply_vm_features
# Description: This function is now deprecated. Feature scripts are now applied
#              via cloud-init.
# =====================================================================================
apply_vm_features() {
    log_info "Applying VM features is now handled by cloud-init."
}

# =====================================================================================
# Function: create_vm_snapshot
# Description: Creates a snapshot of the VM if a snapshot name is defined.
# Arguments:
#   $1 - The VMID of the VM.
# =====================================================================================
create_vm_snapshot() {
    local VMID="$1"
    local vm_config
    vm_config=$(jq -r ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE")
    local snapshot_name
    snapshot_name=$(echo "$vm_config" | jq -r '.template_snapshot_name // ""')

    if [ -z "$snapshot_name" ]; then
        log_info "No template snapshot defined for VM $VMID. Skipping."
        return 0
    fi

    if qm listsnapshot "$VMID" | grep -q "$snapshot_name"; then
        log_info "Snapshot '$snapshot_name' already exists for VM $VMID. Skipping."
        return 0
    fi

    log_info "Creating snapshot '$snapshot_name' for VM $VMID..."
    run_qm_command snapshot "$VMID" "$snapshot_name"
    log_info "Snapshot '$snapshot_name' created successfully."
}

# =====================================================================================
#                                SCRIPT EXECUTION
# =====================================================================================
main() {
    setup_logging "$LOG_FILE"
    parse_arguments "$@"

    if [ "$SETUP_HYPERVISOR" = true ]; then
        setup_hypervisor "$HYPERVISOR_CONFIG_FILE"
        exit_script 0
    fi

    if [ "$PROVISION_TEMPLATE" = true ]; then
        local template_vmid
        template_vmid=$(jq -r '.vms[] | select(.is_template == true) | .vmid' "$VM_CONFIG_FILE")
        if [ -z "$template_vmid" ]; then
            log_fatal "No VM template defined in $VM_CONFIG_FILE. Set 'is_template' to true for one VM."
        fi
        local storage_pool
        storage_pool=$(jq -r '.vm_defaults.storage_pool' "$VM_CONFIG_FILE")
        local network_bridge
        network_bridge=$(jq -r '.vm_defaults.network_bridge' "$VM_CONFIG_FILE")
        
        "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/provision_cloud_template.sh" \
            --vmid "$template_vmid" \
            --storage-pool "$storage_pool" \
            --bridge "$network_bridge"
        exit_script $?
    fi

    if [ -n "$DELETE_ID" ]; then
        # Logic to delete VM or LXC
        log_fatal "Delete functionality is not yet implemented."
        exit_script 1
    fi

    for id in "${CTID_LIST[@]}"; do
        if jq -e ".vms[] | select(.vmid == $id)" "$VM_CONFIG_FILE" > /dev/null; then
            orchestrate_vm "$id"
        elif jq -e ".lxc_configs.\"$id\"" "$LXC_CONFIG_FILE" > /dev/null; then
            orchestrate_lxc "$id"
        else
            log_fatal "ID $id not found in VM or LXC configuration files."
        fi
    done
}

main "$@"