
#!/bin/bash
#
# File: phoenix_orchestrator.sh
# Description: This script is the central orchestrator for the Phoenix Hypervisor system. It serves as the single
#              point of entry for all provisioning, management, and configuration tasks for both LXC containers
#              and QEMU/KVM virtual machines. The orchestrator is designed around a declarative configuration model,
#              reading the desired state from JSON files (`phoenix_hypervisor_config.json`, `phoenix_lxc_configs.json`,
#              and `phoenix_vm_configs.json`) and applying the necessary changes to the system to achieve that state.
#
#              The script implements a state machine to ensure that all operations are idempotent and resumable,
#              making the system resilient to failures. It supports a variety of operations, including hypervisor setup,
#              guest creation (from templates or clones), configuration management, feature installation, and health checks.
#              This convergent design ensures that the system will always move towards the state defined in the
#              configuration files, regardless of its current state.
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: A library of shared shell functions for logging, error handling, and other common tasks.
#   - jq: A command-line JSON processor used to parse the configuration files.
#   - pct: The Proxmox command-line tool for managing LXC containers.
#   - qm: The Proxmox command-line tool for managing QEMU/KVM virtual machines.
#   - ajv-cli: A command-line tool for validating JSON files against a schema (used for configuration validation).
#
# Inputs:
#   - <ID>: A positional argument specifying the ID of the LXC container or VM to orchestrate.
#   - --setup-hypervisor: A flag to trigger the initial setup of the Proxmox hypervisor.
#   - --delete <ID>: A flag to delete the specified LXC container or VM.
#   - --dry-run: An optional flag that enables dry-run mode, which logs the commands that would be executed without
#                actually running them. This is useful for testing and validation.
#   - --reconfigure: A flag to force the reconfiguration of an existing container or VM.
#   - --smoke-test: A flag to run a series of smoke tests to verify the health of the hypervisor and its components.
#   - --test <SUITE>: A flag to run a specific test suite against a container or the hypervisor.
#   - --wipe-disks: A dangerous flag that wipes the disks during hypervisor setup. Use with extreme caution.
#   - Configuration values from `phoenix_hypervisor_config.json`, `phoenix_lxc_configs.json`, and `phoenix_vm_configs.json`.
#
# Outputs:
#   - Log messages to stdout and to a log file located at /var/log/phoenix_hypervisor/orchestrator_*.log.
#   - The output of `pct` and `qm` commands.
#   - Exit codes indicating the success or failure of the orchestration process.
#
# Version: 1.1.0
# Author: Phoenix Hypervisor Team

# --- Determine script's absolute directory ---
# This ensures that all paths are relative to the script's location, making the system more portable.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides a centralized library of shell functions for logging, error handling,
# and other common tasks, ensuring consistency across all scripts in the Phoenix Hypervisor system.
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
# Description: Parses and validates the command-line arguments passed to the script. This function
#              is responsible for determining the desired mode of operation (e.g., hypervisor setup,
#              guest orchestration, deletion) and setting the appropriate global variables. It ensures
#              that the script is invoked with a valid combination of arguments.
#
# Arguments:
#   $@ - All command-line arguments passed to the script.
#
# Returns:
#   None. The function will exit the script with a status code of 2 if the arguments are invalid
#   or if a required argument is missing.
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
# Description: Validates the essential inputs required for the script to operate, such as the
#              presence of the LXC configuration file and the validity of the provided CTID.
#              This function is a critical part of the script's pre-flight checks.
#
# Arguments:
#   $1 - The CTID of the container to validate.
#
# Returns:
#   None. The function will exit the script with a fatal error if any of the inputs are invalid.
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
# Function: check_storage_pool_exists
# Description: Checks if a given storage pool exists on the Proxmox server. This is a crucial
#              pre-flight check to ensure that the storage specified in the configuration is
#              available before attempting to create a container or VM.
#
# Arguments:
#   $1 - The name of the storage pool to check.
#
# Returns:
#   None. The function will exit the script with a fatal error if the storage pool does not exist.
# =====================================================================================
check_storage_pool_exists() {
    local storage_pool_name="$1"
    log_info "Checking for existence of storage pool: $storage_pool_name"

    # The `pvesm status` command lists all available storage pools on the Proxmox server.
    # We parse the output to check if the specified pool is in the list.
    if ! pvesm status | awk 'NR>1 {print $1}' | grep -q "^${storage_pool_name}$"; then
        log_fatal "Storage pool '$storage_pool_name' does not exist on the Proxmox server."
    fi
    log_info "Storage pool '$storage_pool_name' found."
}

# =====================================================================================
# Function: create_container_from_template
# Description: Creates a new LXC container from a specified template file. This function reads
#              all the necessary parameters from the JSON configuration file, constructs the
#              `pct create` command, and executes it. It also handles the downloading of the
#              template if it is not already present on the system.
#
# Arguments:
#   $1 - The CTID of the container to create.
#
# Returns:
#   None. The function will exit the script with a fatal error if the `pct create` command fails.
# =====================================================================================
create_container_from_template() {
    local CTID="$1"
    log_info "Starting creation of container $CTID from template."

    # --- Retrieve all necessary parameters from the config file ---
    # The `jq_get_value` function is a wrapper that simplifies querying the JSON configuration.
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
    # This logic ensures that the required template is available before attempting to create the container.
    local mount_point_base=$(jq -r '.mount_point_base' "$VM_CONFIG_FILE")
    local iso_dataset_path=$(jq -r '.zfs.datasets[] | select(.name == "shared-iso") | .pool + "/" + .name' "$VM_CONFIG_FILE")
    local template_path="${mount_point_base}/${iso_dataset_path}/template/cache/$(basename "$template")"

    if [ ! -f "$template_path" ]; then
        log_info "Template file not found at $template_path. Attempting to download..."
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
    # The network configuration is assembled into a single string as required by the `pct create` command.
    local net0_name=$(jq_get_value "$CTID" ".network_config.name")
    local net0_bridge=$(jq_get_value "$CTID" ".network_config.bridge")
    local net0_ip=$(jq_get_value "$CTID" ".network_config.ip")
    local net0_gw=$(jq_get_value "$CTID" ".network_config.gw")
    local net0_string="name=${net0_name},bridge=${net0_bridge},ip=${net0_ip},gw=${net0_gw},hwaddr=${mac_address}" # Assemble network string

    # --- Build the pct create command array ---
    # Using an array for the command arguments is a best practice that avoids issues with word splitting and quoting.
    local pct_create_cmd=(
        create "$CTID" "$template"
        --hostname "$hostname"
        --memory "$memory_mb"
        --cores "$cores"
        --storage "$storage_pool"
        --rootfs "${storage_pool}:${storage_size_gb}"
        --net0 "$net0_string"
        --unprivileged "$unprivileged_val"
    )

    # Note: The --features flag is reserved for Proxmox's internal use.
    # Custom features (e.g., Docker, Nvidia) are handled by the state machine after container creation.

    # --- Execute the command ---
    # The `run_pct_command` function is a wrapper that handles logging and dry-run mode.
    if ! run_pct_command "${pct_create_cmd[@]}"; then
        log_fatal "'pct create' command failed for CTID $CTID."
    fi
    log_info "Container $CTID created from template successfully."
}

# =====================================================================================
# Function: clone_container
# Description: Clones an LXC container from a specified source container and snapshot. This
#              is a more efficient way to create new containers that are based on a common
#              template. The function performs pre-flight checks to ensure that the source
#              container and snapshot exist before attempting the clone operation.
#
# Arguments:
#   $1 - The CTID of the new container to create.
#
# Returns:
#   None. The function will exit the script with a fatal error if the `pct clone` command fails.
# =====================================================================================
clone_container() {
    local CTID="$1"
    local source_ctid=$(jq_get_value "$CTID" ".clone_from_ctid") # Retrieve source CTID from config
    log_info "Starting clone of container $CTID from source CTID $source_ctid."

    local source_snapshot_name=$(jq_get_value "$source_ctid" ".template_snapshot_name") # Retrieve snapshot name from source CTID config

    # --- Pre-flight checks for cloning ---
    # These checks ensure that the source container and snapshot are available before proceeding.
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
    if ! run_pct_command "${pct_clone_cmd[@]}"; then
        log_fatal "'pct clone' command failed for CTID $CTID."
    fi
    log_info "Container $CTID cloned from $source_ctid successfully."
}


# =====================================================================================
# Function: apply_configurations
# Description: Applies a set of configurations to a newly created or cloned container. This
#              function is responsible for setting the container's resources (memory, cores),
#              network settings, and other options based on the values defined in the JSON
#              configuration file. This is a key step in the idempotent state machine.
#
# Arguments:
#   $1 - The CTID of the container to configure.
#
# Returns:
#   None. The function will exit the script with a fatal error if any of the `pct set` commands fail.
# =====================================================================================
apply_configurations() {
    local CTID="$1"
    log_info "Applying configurations for CTID: $CTID"
    local conf_file="/etc/pve/lxc/${CTID}.conf"

    # --- Retrieve configuration values ---
    local memory_mb=$(jq_get_value "$CTID" ".memory_mb")
    local cores=$(jq_get_value "$CTID" ".cores")
    local features
    features=$(jq_get_value "$CTID" ".features // [] | .[]" || echo "")
    local start_at_boot=$(jq_get_value "$CTID" ".start_at_boot")
    local boot_order=$(jq_get_value "$CTID" ".boot_order")
    local boot_delay=$(jq_get_value "$CTID" ".boot_delay")
    local start_at_boot_val=$([ "$start_at_boot" == "true" ] && echo "1" || echo "0")
 
     # --- Apply core settings ---
     # These commands set the fundamental resource allocations for the container.
    run_pct_command set "$CTID" --memory "$memory_mb" || log_fatal "Failed to set memory."
    run_pct_command set "$CTID" --cores "$cores" || log_fatal "Failed to set cores."
    run_pct_command set "$CTID" --onboot "${start_at_boot_val}" || log_fatal "Failed to set onboot."
    run_pct_command set "$CTID" --startup "order=${boot_order},up=${boot_delay},down=${boot_delay}" || log_fatal "Failed to set startup."
 
    # --- Apply AppArmor Profile ---
    # This function handles the application of the AppArmor profile, which is a critical security feature.
    apply_apparmor_profile "$CTID"

    # --- Apply pct options ---
    # These are Proxmox-specific features that can be enabled on the container.
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
    # These are low-level LXC options that are written directly to the container's configuration file.
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
    # This ensures that the container has the correct network configuration.
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

# =====================================================================================
# Function: ensure_container_defined
# Description: This function is a key part of the idempotent state machine. It checks if a
#              container with the specified CTID already exists. If it does, the function
#              does nothing. If it doesn't, it calls the appropriate function to create the
#              container, either from a template or by cloning another container.
#
# Arguments:
#   $1 - The CTID of the container to check.
#
# Returns:
#   0 on success, 1 on failure (if cloning fails and a retry is needed).
# =====================================================================================
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
# Description: Creates and attaches ZFS volumes to a container. This allows for dedicated
#              storage to be attached to a container, which is useful for applications that
#              require large amounts of storage or specific ZFS features.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if volume creation fails.
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
# Description: Creates and attaches dedicated storage volumes to a container. This is similar
#              to `apply_zfs_volumes` but is intended for more general-purpose storage.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if volume creation fails.
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
# Description: Ensures that the container's root disk size matches the size specified in the
#              configuration file. The `pct resize` command is idempotent, so this function
#              can be run multiple times without causing issues.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if the `pct resize` command fails.
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
# Description: Starts the specified LXC container. This function includes retry logic to
#              handle transient startup issues, making the orchestration process more robust.
#              It also checks if the container is already running to maintain idempotency.
#
# Arguments:
#   $1 - The CTID of the container to start.
#
# Returns:
#   0 on successful container start. The function will exit with a fatal error if the
#   container fails to start after all retries.
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
# Description: Iterates through the 'features' array in the container's JSON configuration
#              and executes the corresponding feature installation script. Each feature script
#              is expected to be idempotent, meaning it can be run multiple times without
#              changing the result beyond the initial application.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if a feature script is not found or fails.
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
# Description: Executes the Portainer feature script for the container if a Portainer role
#              is defined in the configuration. This is a specialized feature that sets up
#              the container as either a Portainer server or agent.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if the script fails.
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
# Description: Executes a final application-specific script for the LXC container if one is
#              defined in its JSON configuration. This allows for application-level setup
#              and configuration to be performed after the container and its features have
#              been provisioned. The script is executed inside the container using `pct exec`.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if the application script is not found or fails.
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
    # This model ensures that the script and its dependencies are available inside the container.
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
# Description: Executes a health check command inside the container if one is defined in
#              the configuration. This allows for application-level health checks to be
#              performed after the container is fully provisioned. The function includes
#              retry logic to handle services that may take some time to start.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if the health check fails after all retries.
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
# Description: Executes post-deployment validation tests for a container if they are defined
#              in the configuration. This allows for automated testing to be performed after
#              a container is provisioned, ensuring that it is functioning correctly.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   0 on success, 1 on failure.
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
# Description: Creates a snapshot of an LXC container if it is designated as a template in
#              the configuration file. This is a key part of the container templating
#              strategy, allowing for new containers to be quickly cloned from a pre-configured
#              template. The function is idempotent and will not create a snapshot if one
#              with the same name already exists.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if snapshot creation fails.
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
# Description: Applies the specified AppArmor profile to the container's configuration file.
#              This is a critical security function that ensures containers are properly
#              sandboxed. It handles both custom profiles and the 'unconfined' state.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if the configuration file is not found
#   or if the AppArmor profile cannot be applied.
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
# Description: A robust wrapper for executing `qm` (Proxmox QEMU/KVM) commands. It handles
#              logging and dry-run mode, ensuring that all VM operations are consistently
#              managed.
#
# Arguments:
#   $@ - The `qm` command and its arguments.
#
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
# Description: A wrapper for executing `pvesm` (Proxmox VE Storage Manager) commands. It
#              handles logging and dry-run mode for storage-related operations.
#
# Arguments:
#   $@ - The `pvesm` command and its arguments.
#
# Returns:
#   0 on success, 1 on failure.
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
# Description: Orchestrates the initial setup of the Proxmox hypervisor by executing a
#              predefined sequence of setup scripts. This function is called when the
#              `--setup-hypervisor` flag is used.
#
# Arguments:
#   $1 - The path to the hypervisor configuration file.
#
# Returns:
#   None. The function will exit with a fatal error if any of the setup scripts fail.
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
# Description: The main state machine for VM provisioning. This function orchestrates the
#              entire lifecycle of a VM, from creation and configuration to feature
#              application and snapshotting.
#
# Arguments:
#   $1 - The VMID of the VM to orchestrate.
#
# Returns:
#   None. The function will exit with a fatal error if any step in the orchestration fails.
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
# Description: Checks if the VM exists. If not, it calls the appropriate function to create
#              the VM, either from a template image or by cloning an existing VM. This is
#              a key part of the idempotent state machine for VMs.
#
# Arguments:
#   $1 - The VMID to check.
#
# Returns:
#   None. The function will exit with a fatal error if the VM definition is invalid.
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
    local template