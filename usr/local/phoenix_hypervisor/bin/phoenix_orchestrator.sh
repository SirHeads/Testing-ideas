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
#   --create-vm <vm_name>: Flag to create a new VM with a specified name.
#   --start-vm <vm_id>: Flag to start a VM with a specified ID.
#   --stop-vm <vm_id>: Flag to stop a VM with a specified ID.
#   --delete-vm <vm_id>: Flag to delete a VM with a specified ID.
#   <CTID>: Positional argument for the Container ID when orchestrating LXC containers.
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
CTID=""
VM_NAME=""
VM_ID=""
DRY_RUN=false # Flag for dry-run mode
SETUP_HYPERVISOR=false # Flag for hypervisor setup mode
CREATE_VM=false
START_VM=false
STOP_VM=false
DELETE_VM=false
LOG_FILE="/var/log/phoenix_hypervisor/orchestrator_$(date +%Y%m%d).log"
VM_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_hypervisor_config.json"
VM_CONFIG_SCHEMA_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_hypervisor_config.schema.json"




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
        log_error "Usage: $0 [--create-vm <vm_name> | --start-vm <vm_id> | --stop-vm <vm_id> | --delete-vm <vm_id> | <CTID>] [--dry-run] | $0 --setup-hypervisor [--dry-run]"
        exit_script 2
    fi

    local operation_mode_set=false # Flag to ensure only one operation mode is set

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true # Enable dry-run mode
                shift
                ;;
            --setup-hypervisor)
                SETUP_HYPERVISOR=true # Enable hypervisor setup mode
                operation_mode_set=true
                shift
                ;;
            --create-vm)
                CREATE_VM=true # Enable VM creation mode
                VM_NAME="$2" # Capture VM name
                operation_mode_set=true
                shift 2
                ;;
            --start-vm)
                START_VM=true # Enable VM start mode
                VM_ID="$2" # Capture VM ID
                operation_mode_set=true
                shift 2
                ;;
            --stop-vm)
                STOP_VM=true # Enable VM stop mode
                VM_ID="$2" # Capture VM ID
                operation_mode_set=true
                shift 2
                ;;
            --delete-vm)
                DELETE_VM=true # Enable VM deletion mode
                VM_ID="$2" # Capture VM ID
                operation_mode_set=true
                shift 2
                ;;
            -*) # Handle unknown flags
                log_error "Unknown option: $1"
                exit_script 2
                ;;
            *) # Handle positional argument (CTID for LXC orchestration)
                # Ensure CTID is not combined with other operation modes
                if [ "$operation_mode_set" = true ]; then
                    log_fatal "Cannot combine CTID with other operation modes (--create-vm, --start-vm, etc.)."
                fi
                CTID="$1" # Capture CTID
                operation_mode_set=true
                shift
                ;;
        esac
    done

    # If no operation mode was set, display usage and exit
    if [ "$operation_mode_set" = false ]; then
        log_fatal "Missing required arguments. Usage: $0 [--create-vm <vm_name> | --start-vm <vm_id> | --stop-vm <vm_id> | --delete-vm <vm_id> | <CTID>] [--dry-run] | $0 --setup-hypervisor [--dry-run]"
    fi

    # Log the determined operation mode and validate specific arguments
    if [ "$SETUP_HYPERVISOR" = true ]; then
        log_info "Hypervisor setup mode enabled."
    elif [ "$CREATE_VM" = true ]; then
        if [ -z "$VM_NAME" ]; then # Ensure VM name is provided for creation
            log_fatal "Missing VM name for --create-vm. Usage: $0 --create-vm <vm_name>"
        fi
        log_info "VM creation mode for VM: $VM_NAME"
    elif [ "$START_VM" = true ]; then
        if [ -z "$VM_ID" ]; then # Ensure VM ID is provided for starting
            log_fatal "Missing VM ID for --start-vm. Usage: $0 --start-vm <vm_id>"
        fi
        log_info "VM start mode for VM ID: $VM_ID"
    elif [ "$STOP_VM" = true ]; then
        if [ -z "$VM_ID" ]; then # Ensure VM ID is provided for stopping
            log_fatal "Missing VM ID for --stop-vm. Usage: $0 --stop-vm <vm_id>"
        fi
        log_info "VM stop mode for VM ID: $VM_ID"
    elif [ "$DELETE_VM" = true ]; then
        if [ -z "$VM_ID" ]; then # Ensure VM ID is provided for deletion
            log_fatal "Missing VM ID for --delete-vm. Usage: $0 --delete-vm <vm_id>"
        fi
        log_info "VM delete mode for VM ID: $VM_ID"
    else
        if [ -z "$CTID" ]; then # Ensure CTID is provided for LXC orchestration
            log_fatal "Missing CTID for container orchestration. Usage: $0 <CTID> [--dry-run]"
        fi
        log_info "Container orchestration mode for CTID: $CTID"
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
    log_info "Starting input validation..."
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
# Function: handle_defined_state
# Description: Handles the 'defined' state by creating or cloning the container
#              based on the configuration.
# =====================================================================================
# =====================================================================================
# Function: handle_defined_state
# Description: Manages the 'defined' state for an LXC container. It determines
#              whether to clone an existing container or create a new one from a
#              template based on the configuration.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None.
# =====================================================================================
handle_defined_state() {
    log_info "Handling 'defined' state for CTID: $CTID"
    local clone_from_ctid # Variable to store the source CTID for cloning
    clone_from_ctid=$(jq_get_value "$CTID" ".clone_from_ctid" || echo "") # Retrieve clone_from_ctid from config

    # If clone_from_ctid is specified, clone the container; otherwise, create from template
    if [ -n "$clone_from_ctid" ]; then
        clone_container
    else
        create_container_from_template
    fi
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
    local source_ctid=$(jq_get_value "$CTID" ".clone_from_ctid") # Retrieve source CTID from config
    log_info "Starting clone of container $CTID from source CTID $source_ctid."

    local source_snapshot_name=$(jq_get_value "$source_ctid" ".template_snapshot_name") # Retrieve snapshot name from source CTID config

    # --- Pre-flight checks for cloning ---
    # Perform pre-flight checks: ensure source container exists and snapshot is present
    if ! pct status "$source_ctid" > /dev/null 2>&1; then
        log_fatal "Source container $source_ctid does not exist."
    fi
    if ! pct listsnapshot "$source_ctid" | grep -q "$source_snapshot_name"; then
        log_fatal "Snapshot '$source_snapshot_name' not found on source container $source_ctid."
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
# Function: handle_created_state
# Description: Handles the 'created' state by applying configurations.
# =====================================================================================
# =====================================================================================
# Function: handle_created_state
# Description: Manages the 'created' state for an LXC container by applying its
#              defined configurations.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None.
# =====================================================================================
handle_created_state() {
    log_info "Handling 'created' state for CTID: $CTID"
    apply_configurations # Call function to apply configurations
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
    log_info "Applying configurations for CTID: $CTID"

    # --- Retrieve configuration values ---
    # Retrieve configuration values from the JSON config
    local memory_mb=$(jq_get_value "$CTID" ".memory_mb")
    local cores=$(jq_get_value "$CTID" ".cores")
    local features=$(jq_get_value "$CTID" ".features[]" || echo "") # Retrieve features as an array

    # --- Apply core settings ---
    # Apply core settings: memory and CPU cores
    run_pct_command set "$CTID" --memory "$memory_mb" || log_fatal "Failed to set memory."
    run_pct_command set "$CTID" --cores "$cores" || log_fatal "Failed to set cores."

   # --- Apply pct options ---
   local pct_options
   pct_options=$(jq_get_value "$CTID" ".pct_options // [] | .[]" || echo "")
   if [ -n "$pct_options" ]; then
       log_info "Applying pct options for CTID $CTID..."
       for option in $pct_options; do
          if [[ "$option" == "nesting=1" ]]; then
              run_pct_command set "$CTID" --features "$option" || log_fatal "Failed to set pct option: $option"
          else
              run_pct_command set "$CTID" --"$option" || log_fatal "Failed to set pct option: $option"
          fi
       done
   fi

    # --- Enable Nesting for Docker ---
    # Enable nesting feature if 'docker' is specified, which is required for Docker-in-LXC
    if [[ " ${features[*]} " =~ " docker " ]]; then
        log_info "Docker feature detected. Enabling nesting for CTID $CTID..."
        run_pct_command set "$CTID" --features nesting=1 || log_fatal "Failed to enable nesting."
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

# =====================================================================================
# Function: ensure_container_disk_size
# Description: Ensures the container's root disk size matches the configuration.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if the `pct resize` command fails.
# =====================================================================================
ensure_container_disk_size() {
    log_info "Ensuring correct disk size for CTID: $CTID"
    local storage_size_gb
    storage_size_gb=$(jq_get_value "$CTID" ".storage_size_gb")

    # The pct resize command is idempotent for our purposes.
    # It sets the disk to the specified size.
    run_pct_command resize "$CTID" rootfs "${storage_size_gb}G"
    log_info "Disk size for CTID $CTID set to ${storage_size_gb}G."
}

# =====================================================================================
# Function: handle_configured_state
# Description: Handles the 'configured' state by starting the container.
# =====================================================================================
# =====================================================================================
# Function: handle_configured_state
# Description: Manages the 'configured' state for an LXC container by initiating
#              the container startup process.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None.
# =====================================================================================
handle_configured_state() {
    log_info "Handling 'configured' state for CTID: $CTID"
    start_container # Call function to start the container
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
    log_info "Attempting to start container CTID: $CTID with retries..."
    local attempts=0 # Counter for startup attempts
    local max_attempts=3 # Maximum number of startup attempts
    local interval=5 # Delay between retries in seconds

    # Loop to attempt container startup with retries
    while [ "$attempts" -lt "$max_attempts" ]; do
        if run_pct_command start "$CTID"; then # Attempt to start the container
            log_info "Container $CTID started successfully."
            return 0 # Return success if container starts
        else
            attempts=$((attempts + 1)) # Increment attempt counter
            log_error "WARNING: 'pct start' command failed for CTID $CTID (Attempt $attempts/$max_attempts)."
            if [ "$attempts" -lt "$max_attempts" ]; then
                log_info "Retrying in $interval seconds..."
                sleep "$interval" # Wait before retrying
            fi
        fi
    done

    log_fatal "Container $CTID failed to start after $max_attempts attempts."
}

# =====================================================================================
# Function: handle_running_state
# Description: Handles the 'running' state. This is the final state, so no
#              action is taken.
# =====================================================================================
# =====================================================================================
# Function: handle_running_state
# Description: Manages the 'running' state for an LXC container by applying
#              any defined feature scripts.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None.
# =====================================================================================
handle_running_state() {
    log_info "Handling 'running' state for CTID: $CTID"
    apply_features # Call function to apply features
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
    log_info "Applying features for CTID: $CTID"
    local features # Variable to store the list of features
    features=$(jq_get_value "$CTID" ".features[]" || echo "") # Retrieve features as an array from config

    # If no features are defined, log and exit
    if [ -z "$features" ]; then
        log_info "No features to apply for CTID $CTID."
        return 0
    fi

    # Loop through each feature and execute its corresponding script
    for feature in $features; do
        local feature_script_path="${PHOENIX_BASE_DIR}/bin/lxc_setup/phoenix_hypervisor_feature_install_${feature}.sh" # Construct script path
        log_info "Executing feature: $feature ($feature_script_path)"

        # Check if the feature script exists
        if [ ! -f "$feature_script_path" ]; then
            log_fatal "Feature script not found at $feature_script_path."
        fi

        # Execute the feature script, passing the CTID as an argument
        if ! "$feature_script_path" "$CTID"; then
            log_fatal "Feature script '$feature' failed for CTID $CTID."
        fi
    done

    log_info "All features applied successfully for CTID $CTID."
}

# =====================================================================================
# Function: handle_customizing_state
# Description: Handles the 'customizing' state. This is the final state after
#              all features have been applied.
# =====================================================================================
# =====================================================================================
# Function: handle_customizing_state
# Description: Manages the 'customizing' state for an LXC container, which is reached
#              after all feature scripts have been applied. It then proceeds to run
#              any defined application script.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None.
# =====================================================================================
handle_customizing_state() {
    log_info "Container $CTID has been fully customized."
    run_application_script # Call function to run the application script
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

    # 3b. Copy the LXC config file to the container's temp directory
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
    if ! run_pct_command snapshot "$CTID" "$snapshot_name"; then
        log_fatal "Failed to create snapshot '$snapshot_name' for CTID $CTID."
    fi
    log_info "Snapshot '$snapshot_name' created successfully."
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
# Function: create_vm
# Description: Creates a new VM based on a definition in the configuration file.
# Arguments:
#   $1 - The name of the VM to create.
# =====================================================================================
# =====================================================================================
# Function: create_vm
# Description: Creates a new virtual machine (VM) based on a definition in the
#              configuration file, applies default settings, and executes post-creation scripts.
# Arguments:
#   $1 (vm_name) - The name of the VM to create.
# Returns:
#   None. Exits with a fatal error if VM configuration is not found, or if `qm`
#   commands or post-creation scripts fail.
# =====================================================================================
create_vm() {
    local vm_name="$1" # Name of the VM to create
    log_info "Attempting to create VM: $vm_name"

    # 1. Parse Configuration
    # Parse VM configuration from the VM_CONFIG_FILE
    local vm_config
    vm_config=$(jq ".vms[] | select(.name == \"$vm_name\")" "$VM_CONFIG_FILE")

    # Check if VM configuration was found
    if [ -z "$vm_config" ]; then
        log_fatal "VM configuration for '$vm_name' not found in $VM_CONFIG_FILE."
    fi

    # 2. Apply Defaults
    # Apply default VM settings if not explicitly defined in the VM's configuration
    local vm_defaults
    vm_defaults=$(jq ".vm_defaults" "$VM_CONFIG_FILE")

    local template=$(echo "$vm_config" | jq -r ".template // \"$(echo "$vm_defaults" | jq -r ".template")\"") # VM template
    local cores=$(echo "$vm_config" | jq -r ".cores // $(echo "$vm_defaults" | jq -r ".cores")") # Number of CPU cores
    local memory_mb=$(echo "$vm_config" | jq -r ".memory_mb // $(echo "$vm_defaults" | jq -r ".memory_mb")") # Memory in MB
    local disk_size_gb=$(echo "$vm_config" | jq -r ".disk_size_gb // $(echo "$vm_defaults" | jq -r ".disk_size_gb")") # Disk size in GB
    local storage_pool=$(echo "$vm_config" | jq -r ".storage_pool // \"$(echo "$vm_defaults" | jq -r ".storage_pool")\"") # Storage pool
    local network_bridge=$(echo "$vm_config" | jq -r ".network_bridge // \"$(echo "$vm_defaults" | jq -r ".network_bridge")\"") # Network bridge
    local post_create_scripts=$(echo "$vm_config" | jq -c ".post_create_scripts // []") # Post-creation scripts

    # Generate a unique VM ID (e.g., starting from 9000 and finding the next available)
    # Generate a unique VM ID, starting from 9000 and incrementing until an unused ID is found
    local vm_id=9000
    while qm status "$vm_id" > /dev/null 2>&1; do
        vm_id=$((vm_id + 1))
    done
    log_info "Assigned VM ID: $vm_id"

    # 3. Create VM
    log_info "Creating VM $vm_name (ID: $vm_id) from template $template..."
    # Construct the `qm create` command array
    local qm_create_cmd=(
        qm create "$vm_id" # VM ID
        --name "$vm_name" # VM name
        --memory "$memory_mb" # Allocated memory
        --cores "$cores" # Number of CPU cores
        --net0 "virtio,bridge=${network_bridge}" # Network configuration
        --ostype "l26" # OS type (Linux 2.6+ kernel)
        --scsi0 "${storage_pool}:${disk_size_gb},import-from=${template}" # SCSI disk with import from template
    )

    # Execute the `qm create` command
    if ! run_qm_command "${qm_create_cmd[@]}"; then
        log_fatal "'qm create' command failed for VM $vm_name (ID: $vm_id)."
    fi

    # Set boot order
    # Set the boot order for the VM
    log_info "Setting boot order for VM $vm_id..."
    if ! run_qm_command set "$vm_id" --boot "order=scsi0"; then
        log_fatal "'qm set boot order' command failed for VM $vm_id."
    fi

    log_info "VM $vm_name (ID: $vm_id) created successfully."

    # 4. Post-Creation Setup
    # Execute post-creation scripts if defined
    if [ "$(echo "$post_create_scripts" | jq 'length')" -gt 0 ]; then
        log_info "Executing post-creation scripts for VM $vm_name (ID: $vm_id)..."
        start_vm "$vm_id" # Start the VM to allow execution of post-creation scripts

        # Wait for VM to boot and get an IP address (simplified, can be improved)
        # Wait for the VM to boot and acquire an IP address (simplified, can be improved with actual IP detection)
        log_info "Waiting for VM $vm_id to boot and acquire an IP address..."
        sleep 30 # Placeholder: Adjust sleep duration as needed for VM boot time

        # Iterate through each post-creation script and execute it
        for script in $(echo "$post_create_scripts" | jq -r '.[]'); do
            local script_path="$(dirname "$0")/bin/${script}" # Construct full path to the script
            log_info "Executing post-create script: $script for VM $vm_id"
            # Check if the script file exists
            if [ ! -f "$script_path" ]; then
                log_fatal "Post-create script not found at $script_path."
            fi
            # Note: This assumes the script can be run remotely (e.g., via SSH or qm agent).
            # For simplicity, we're directly executing it on the orchestrator host,
            # passing the VM_ID as an argument. In a real scenario, `qm agent exec` or SSH would be used.
            log_info "Simulating execution of $script inside VM $vm_id."
            if ! "$script_path" "$vm_id"; then # Execute the script, passing VM_ID
                log_fatal "Post-create script '$script' failed for VM $vm_id."
            fi
        done
        log_info "All post-creation scripts executed for VM $vm_name (ID: $vm_id)."
    else
        log_info "No post-creation scripts defined for VM $vm_name."
    fi

    log_info "VM $vm_name (ID: $vm_id) is ready."
}

# =====================================================================================
# Function: start_vm
# Description: Starts an existing VM.
# Arguments:
#   $1 - The ID of the VM to start.
# =====================================================================================
# =====================================================================================
# Function: start_vm
# Description: Starts an existing virtual machine (VM) with the given ID.
# Arguments:
#   $1 (vm_id) - The ID of the VM to start.
# Returns:
#   0 if the VM is already running or starts successfully, exits with a fatal
#   error if the VM does not exist or fails to start.
# =====================================================================================
start_vm() {
    local vm_id="$1" # ID of the VM to start
    log_info "Attempting to start VM ID: $vm_id"

    # Check if the VM exists
    if ! qm status "$vm_id" > /dev/null 2>&1; then
        log_fatal "VM ID $vm_id does not exist."
    fi

    # Check if the VM is already running
    if qm status "$vm_id" | grep -q "running"; then
        log_info "VM ID $vm_id is already running."
        return 0
    fi

    # Execute the `qm start` command
    if ! run_qm_command start "$vm_id"; then
        log_fatal "'qm start' command failed for VM ID $vm_id."
    fi
    log_info "VM ID $vm_id started successfully."
}

# =====================================================================================
# Function: stop_vm
# Description: Stops an existing VM.
# Arguments:
#   $1 - The ID of the VM to stop.
# =====================================================================================
# =====================================================================================
# Function: stop_vm
# Description: Stops an existing virtual machine (VM) with the given ID.
# Arguments:
#   $1 (vm_id) - The ID of the VM to stop.
# Returns:
#   0 if the VM is already stopped or stops successfully, exits with a fatal
#   error if the VM does not exist or fails to stop.
# =====================================================================================
stop_vm() {
    local vm_id="$1" # ID of the VM to stop
    log_info "Attempting to stop VM ID: $vm_id"

    # Check if the VM exists
    if ! qm status "$vm_id" > /dev/null 2>&1; then
        log_fatal "VM ID $vm_id does not exist."
    fi

    # Check if the VM is already stopped
    if qm status "$vm_id" | grep -q "stopped"; then
        log_info "VM ID $vm_id is already stopped."
        return 0
    fi

    # Execute the `qm stop` command
    if ! run_qm_command stop "$vm_id"; then
        log_fatal "'qm stop' command failed for VM ID $vm_id."
    fi
    log_info "VM ID $vm_id stopped successfully."
}

# =====================================================================================
# Function: delete_vm
# Description: Deletes an existing VM.
# Arguments:
#   $1 - The ID of the VM to delete.
# =====================================================================================
# =====================================================================================
# Function: delete_vm
# Description: Deletes an existing virtual machine (VM) with the given ID.
#              It first ensures the VM is stopped before attempting deletion.
# Arguments:
#   $1 (vm_id) - The ID of the VM to delete.
# Returns:
#   0 if the VM does not exist or is deleted successfully, exits with a fatal
#   error if deletion fails.
# =====================================================================================
delete_vm() {
    local vm_id="$1" # ID of the VM to delete
    log_info "Attempting to delete VM ID: $vm_id"

    # Check if the VM exists; if not, there's nothing to delete
    if ! qm status "$vm_id" > /dev/null 2>&1; then
        log_info "VM ID $vm_id does not exist. Nothing to delete."
        return 0
    fi

    # Ensure VM is stopped before deleting
    # Ensure the VM is stopped before attempting deletion
    if qm status "$vm_id" | grep -q "running"; then
        log_info "VM ID $vm_id is running. Attempting to stop before deletion."
        stop_vm "$vm_id" # Call stop_vm function
    fi

    # Execute the `qm destroy` command to delete the VM
    if ! run_qm_command destroy "$vm_id"; then
        log_fatal "'qm destroy' command failed for VM ID $vm_id."
    fi
    log_info "VM ID $vm_id deleted successfully."
}

# =====================================================================================
# Function: handle_hypervisor_setup_state
# Description: Orchestrates the execution of hypervisor setup scripts.
# =====================================================================================
# =====================================================================================
# Function: handle_hypervisor_setup_state
# Description: Orchestrates the execution of hypervisor setup scripts. It reads and
#              validates the hypervisor configuration, then sequentially executes
#              a predefined list of setup feature scripts.
# Arguments:
#   None (uses global HYPERVISOR_CONFIG_FILE, HYPERVISOR_CONFIG_SCHEMA_FILE).
# Returns:
#   None. Exits with a fatal error if configuration validation fails or any
#   setup script is not found or fails.
# =====================================================================================
handle_hypervisor_setup_state() {
    log_info "Starting hypervisor setup orchestration."

    # 1. Read and validate hypervisor_config.json
    # Read and validate hypervisor_config.json against its schema
    log_info "Reading and validating hypervisor configuration from $VM_CONFIG_FILE..."
    if [ ! -f "$VM_CONFIG_FILE" ]; then
        log_fatal "Hypervisor configuration file not found at $VM_CONFIG_FILE."
    fi
    if [ ! -f "$VM_CONFIG_SCHEMA_FILE" ]; then
        log_fatal "Hypervisor configuration schema file not found at $VM_CONFIG_SCHEMA_FILE."
    fi

    # Validate the configuration file using `ajv` against its schema
    if ! ajv validate -s "$VM_CONFIG_SCHEMA_FILE" -d "$VM_CONFIG_FILE"; then
        log_fatal "Hypervisor configuration validation failed. Please check $VM_CONFIG_FILE against $VM_CONFIG_SCHEMA_FILE."
    fi
    log_info "Hypervisor configuration validated successfully."

    # Execute hypervisor feature scripts in a predefined sequence
    log_info "Executing hypervisor setup feature scripts..."

    local hypervisor_scripts=(
        "hypervisor_initial_setup.sh"
        "hypervisor_feature_setup_zfs.sh"
        "hypervisor_feature_install_nvidia.sh"
        "hypervisor_feature_create_admin_user.sh"
        "hypervisor_feature_setup_nfs.sh"
        "hypervisor_feature_setup_samba.sh"
    )

    for script_name in "${hypervisor_scripts[@]}"; do # Iterate through each script name
        local script_path="$(dirname "$0")/hypervisor_setup/$script_name" # Construct full script path
        log_info "Executing hypervisor script: $script_name"

        # Check if the script file exists
        if [ ! -f "$script_path" ]; then
            log_error "Hypervisor setup script not found at $script_path."
            continue # Skip to the next script
        fi

        # Execute the hypervisor setup script
        if [[ "$script_name" == "hypervisor_feature_setup_zfs.sh" ]]; then
            if ! "$script_path"; then
                log_error "Hypervisor setup script '$script_name' failed."
            fi
        else
            if ! "$script_path" "$VM_CONFIG_FILE"; then
                log_error "Hypervisor setup script '$script_name' failed."
            fi
        fi
    done

    echo "------------------------------------------------------------"
    echo "Running post-setup verification tests..."
    echo "------------------------------------------------------------"
    /usr/local/phoenix_hypervisor/bin/tests/phoenix_hypervisor_tests.sh 2>&1 | tee -a "$LOG_FILE"
    log_info "Hypervisor setup verification complete. Please review the test output above."

    log_info "All hypervisor setup scripts executed successfully."
}

# =====================================================================================
# Function: setup_logging
# Description: Sets up the logging by creating the log directory and file.
# =====================================================================================
# =====================================================================================
# Function: setup_logging
# Description: Initializes the logging environment by creating the log directory
#              and the main log file if they do not already exist.
# Arguments:
#   None (uses global LOG_FILE).
# Returns:
#   None. Exits with a fatal error if log directory or file creation fails.
# =====================================================================================
setup_logging() {
    local log_dir # Variable to store the log directory path
    log_dir=$(dirname "$LOG_FILE") # Extract directory from LOG_FILE path
    # Create log directory if it doesn't exist
    if [ ! -d "$log_dir" ]; then
        if ! mkdir -p "$log_dir"; then
            echo "FATAL: Failed to create log directory at $log_dir." >&2
            exit 1
        fi
    fi
    # Create log file if it doesn't exist
    if ! touch "$LOG_FILE"; then
        echo "FATAL: Failed to create log file at $LOG_FILE." >&2
        exit 1
    fi
}

# =====================================================================================
# Function: check_dependencies
# Description: Checks for necessary command-line tools and installs them if missing.
# =====================================================================================
# =====================================================================================
# Function: disable_proxmox_enterprise_repos
# Description: Temporarily disables Proxmox enterprise repositories to prevent apt update failures.
# =====================================================================================
disable_proxmox_enterprise_repos() {
    local repo_dir="/etc/apt/sources.list.d"
    log_info "Disabling Proxmox enterprise and Ceph repositories..."

    # Loop through all files in the repository directory
    for file in "$repo_dir"/*; do
        # Check if the file is a regular file and not already disabled
        if [ -f "$file" ] && [[ "$file" != *.disabled ]]; then
            # Check if the filename contains 'pve-enterprise' or 'ceph'
            if [[ "$file" =~ pve-enterprise ]] || [[ "$file" =~ ceph ]]; then
                local disabled_file="${file}.disabled"
                log_info "Disabling repository: $file -> $disabled_file"
                mv "$file" "$disabled_file" || log_fatal "Failed to disable repository $file."
            fi
        fi
    done
    log_info "Proxmox enterprise and Ceph repositories disabled."
}

# =====================================================================================
# Function: enable_proxmox_enterprise_repos
# Description: Re-enables Proxmox enterprise and Ceph repositories.
# =====================================================================================
enable_proxmox_enterprise_repos() {
    local repo_dir="/etc/apt/sources.list.d"
    log_info "Enabling Proxmox enterprise and Ceph repositories..."

    # Loop through all files in the repository directory
    for file in "$repo_dir"/*; do
        # Check if the file is a regular file and ends with '.disabled'
        if [ -f "$file" ] && [[ "$file" == *.disabled ]]; then
            # Check if the filename contains 'pve-enterprise' or 'ceph'
            if [[ "$file" =~ pve-enterprise ]] || [[ "$file" =~ ceph ]]; then
                local enabled_file="${file%.disabled}"
                log_info "Enabling repository: $file -> $enabled_file"
                mv "$file" "$enabled_file" || log_fatal "Failed to enable repository $file."
            fi
        fi
    done
    log_info "Proxmox enterprise and Ceph repositories enabled."
}

# =====================================================================================
# Function: check_dependencies
# Description: Checks for necessary command-line tools and installs them if missing.
# =====================================================================================
check_dependencies() {
    log_info "Checking for dependencies..."
    local dependencies=("jq" "pct" "qm" "ajv")
    local missing_dependencies=()

    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_dependencies+=("$cmd")
        fi
    done

    if [ ${#missing_dependencies[@]} -ne 0 ]; then
        log_info "Missing dependencies: ${missing_dependencies[*]}. Attempting to install..."
        
        # Temporarily disable enterprise repos to avoid apt update failures
        disable_proxmox_enterprise_repos
        
        if ! apt-get update; then
            log_fatal "Failed to update apt repositories. Please check your internet connection and repository configuration."
        fi

        for cmd in "${missing_dependencies[@]}"; do
            case "$cmd" in
                jq)
                    if ! apt-get install -y jq; then
                        log_fatal "Failed to install jq. Please install it manually."
                    fi
                    ;;
                ajv)
                    if ! command -v node > /dev/null || ! command -v npm > /dev/null; then
                        log_info "Node.js or npm not found. Attempting to install..."
                        if ! apt-get install -y nodejs npm; then
                            log_fatal "Failed to install Node.js and npm. Please install them manually."
                        fi
                        log_info "Node.js and npm installed successfully."
                    fi
                    if ! npm install -g ajv-cli; then
                        log_fatal "Failed to install ajv-cli. Please ensure you have Node.js and npm installed and that the installation is working correctly."
                    fi
                    ;;
                # pct and qm are part of Proxmox, so we don't install them here.
                # If they are missing, something is seriously wrong with the environment.
            esac
        done
        
        # Re-enable enterprise repos
        enable_proxmox_enterprise_repos
    else
        log_info "All dependencies are satisfied."
    fi
}

# =====================================================================================
# Function: main
# Description: The main entry point for the Phoenix Orchestrator script. It sets up
#              logging, parses arguments, and then dispatches to appropriate handler
#              functions based on the requested operation mode (hypervisor setup,
#              VM management, or LXC container orchestration).
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   Exits with status 0 on successful completion, or a non-zero status on failure
#   (handled by exit_script).
# =====================================================================================
main() {
    # Initial Setup: Configure logging and redirect stdout/stderr
    setup_logging
    exec &> >(tee -a "$LOG_FILE") # Redirect stdout/stderr to screen and log file


    check_dependencies

    log_info "============================================================"
    log_info "Phoenix Orchestrator Started"
    log_info "============================================================"

    parse_arguments "$@" # Parse command-line arguments

    # Dispatch to the appropriate handler function based on the operation mode
    if [ "$SETUP_HYPERVISOR" = true ]; then
        handle_hypervisor_setup_state # Handle hypervisor setup
    elif [ "$CREATE_VM" = true ]; then
        create_vm "$VM_NAME" # Create a new VM
    elif [ "$START_VM" = true ]; then
        start_vm "$VM_ID" # Start an existing VM
    elif [ "$STOP_VM" = true ]; then
        stop_vm "$VM_ID" # Stop an existing VM
    elif [ "$DELETE_VM" = true ]; then
        delete_vm "$VM_ID" # Delete an existing VM
    else
        validate_inputs # Validate inputs for LXC container orchestration
        # Stateless Orchestration Workflow for LXC Containers
        log_info "Starting stateless orchestration for CTID $CTID..."

        # 1. Ensure Container Exists
        # 1. Ensure Container Exists: Create if it doesn't, otherwise skip
        if ! pct status "$CTID" > /dev/null 2>&1; then
            log_info "Container $CTID does not exist. Proceeding with creation..."
            handle_defined_state # Create or clone the container
        else
            log_info "Container $CTID already exists. Skipping creation."
        fi

        # 2. Ensure Container is Configured: Apply configurations (idempotent)
        log_info "Ensuring container $CTID is correctly configured..."
        ensure_container_disk_size # Ensure disk size is correct
        apply_configurations # Apply configurations to the container

        # 3. Ensure Container is Running
        # 3. Ensure Container is Running: Start if not running, otherwise skip
        if ! pct status "$CTID" | grep -q "running"; then
            log_info "Container $CTID is not running. Attempting to start..."
            start_container # Start the container
        else
            log_info "Container $CTID is already running."
        fi

        # 4. Apply Features: Execute feature scripts (designed to be idempotent)
        log_info "Applying all features to container $CTID..."
        apply_features # Apply feature scripts

        # 5. Run Application Script: Execute application script (should be idempotent)
        log_info "Executing application script for container $CTID..."
        run_application_script # Run the application script

        # 6. Create Template Snapshot: Create a snapshot if the container is a template
        create_template_snapshot # Create a template snapshot

        log_info "Stateless orchestration for CTID $CTID completed."
    fi

    log_info "============================================================"
    log_info "Phoenix Orchestrator Finished"
    log_info "============================================================"
    exit_script 0
}

# --- Script Execution ---
# Call the main function with all command-line arguments to start execution.
main "$@"