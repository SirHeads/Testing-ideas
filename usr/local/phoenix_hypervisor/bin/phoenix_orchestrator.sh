
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
CTID_LIST=()
VM_NAME=""
VM_ID=""
DRY_RUN=false # Flag for dry-run mode
SETUP_HYPERVISOR=false # Flag for hypervisor setup mode
CREATE_VM=false
START_VM=false
STOP_VM=false
DELETE_VM=false
RECONFIGURE=false
LETSGO=false
SMOKE_TEST=false # Flag for smoke test mode
WIPE_DISKS=false # Flag to wipe disks during hypervisor setup
LOG_FILE="/var/log/phoenix_hypervisor/orchestrator_$(date +%Y%m%d).log"
VM_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_hypervisor_config.json"
VM_CONFIG_SCHEMA_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_hypervisor_config.schema.json"
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
        log_error "Usage: $0 [--create-vm <vm_name> | --start-vm <vm_id> | --stop-vm <vm_id> | --delete-vm <vm_id> | <CTID>] [--dry-run] | $0 --setup-hypervisor [--dry-run] | $0 <CTID> --reconfigure | $0 --LetsGo | $0 --smoke-test"
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
            -*) # Handle unknown flags
                log_error "Unknown option: $1"
                exit_script 2
                ;;
            *) # Handle positional arguments (CTIDs for LXC orchestration)
                if [ "$operation_mode_set" = true ] && [ "$LETSGO" = false ]; then
                    log_fatal "Cannot combine CTID with other operation modes (--create-vm, --start-vm, etc.)."
                fi
                # Append all remaining arguments to the CTID list
                while [[ "$#" -gt 0 ]] && ! [[ "$1" =~ ^-- ]]; do
                    CTID_LIST+=("$1")
                    shift
                done
                operation_mode_set=true
                # This allows --dry-run to appear after the CTIDs
                if [[ "$#" -gt 0 ]]; then
                   continue
                fi
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
    elif [ "$LETSGO" = true ]; then
        log_info "LetsGo mode enabled. Orchestrating all containers based on boot order."
    elif [ "$SMOKE_TEST" = true ]; then
        log_info "Smoke test mode enabled."
    else
        if [ ${#CTID_LIST[@]} -eq 0 ]; then # Ensure at least one CTID is provided
            log_fatal "Missing CTID for container orchestration. Usage: $0 <CTID>... [--dry-run]"
        fi
        log_info "Container orchestration mode for CTIDs: ${CTID_LIST[*]}"
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
            if [[ "$option" == "nesting=1" ]]; then
                local apparmor_manages_nesting
                apparmor_manages_nesting=$(jq_get_value "$CTID" ".apparmor_manages_nesting" || echo "false")
                if [ "$apparmor_manages_nesting" = true ]; then
                    log_info "AppArmor profile manages nesting. Skipping explicit 'nesting=1' feature to prevent conflicts."
                else
                    log_info "Adding 'nesting=1' to features to be set."
                    features_to_set+=("$option")
                fi
            else
                features_to_set+=("$option")
            fi
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

        if ! "$feature_script_path" "$CTID"; then
            log_fatal "Feature script '$feature' failed for CTID $CTID."
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
    local run_tests
    run_tests=$(jq_get_value "$CTID" ".run_integration_tests" || echo "false")

    if [ "$run_tests" != "true" ]; then
        log_info "Post-deployment validation skipped for CTID $CTID (run_integration_tests is not true)."
        return 0
    fi

    log_info "Starting post-deployment validation for CTID $CTID..."
    local test_script_path="/usr/local/phoenix_hypervisor/bin/tests/run_vllm_integration_tests.sh"

    if ! "$test_script_path" "$CTID"; then
        log_fatal "Post-deployment validation failed for CTID $CTID."
    fi

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
        local profile_file="/etc/apparmor.d/${apparmor_profile}"
        if [ -f "$profile_file" ]; then
            log_info "Loading AppArmor profile from $profile_file"
            if ! apparmor_parser -r "$profile_file"; then
                log_fatal "Failed to load AppArmor profile $apparmor_profile"
            fi
        else
            log_fatal "AppArmor profile file $profile_file not found"
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
        done
    fi
}

# =====================================================================================
# Function: run_smoke_tests
# Description: Orchestrates a series of health checks against critical services
#              to ensure the environment is stable and operational.
# =====================================================================================
run_smoke_tests() {
    log_info "Starting smoke tests..."
    local all_tests_passed=true

    # Define the services to be checked, their container IDs, and parameters
    local services_to_check=(
        "953:nginx"
        "950:vllm:8000"
        "952:qdrant"
    )

    for service_entry in "${services_to_check[@]}"; do
        IFS=':' read -r ctid service port <<< "$service_entry"
        log_info "Checking service '$service' in container '$ctid'..."

        local health_check_script="health_checks/check_service_status.sh"
        local script_in_container="/tmp/check_service_status.sh"

        # Copy the script to the container
        if ! pct push "$ctid" "${PHOENIX_BASE_DIR}/bin/${health_check_script}" "$script_in_container" >/dev/null 2>&1; then
            log_error "Failed to copy health check script to container $ctid."
            all_tests_passed=false
            continue
        fi

        # Make the script executable
        if ! pct exec "$ctid" -- chmod +x "$script_in_container"; then
            log_error "Failed to make health check script executable in container $ctid."
            all_tests_passed=false
            continue
        fi

        # Build the command to execute inside the container
        local exec_cmd=("$script_in_container" "--service" "$service")
        if [ -n "$port" ]; then
            exec_cmd+=("--port" "$port")
        fi

        # Execute the health check
        if ! pct exec "$ctid" -- "${exec_cmd[@]}"; then
            log_error "Smoke test failed for service '$service' in container '$ctid'."
            all_tests_passed=false
        else
            log_info "Smoke test passed for service '$service' in container '$ctid'."
        fi

        # Clean up the script
        pct exec "$ctid" -- rm "$script_in_container" >/dev/null 2>&1
    done

    if [ "$all_tests_passed" = true ]; then
        log_info "All smoke tests passed successfully."
        exit_script 0
    else
        log_fatal "One or more smoke tests failed."
    fi
}

# =====================================================================================
# Function: all_dependencies_built
# Description: Checks if all dependencies for a given container have been built.
# Arguments:
#   $1 - CTID of the container to check.
#   $2 - Array of built CTIDs.
# Returns:
#   0 if all dependencies are built, 1 otherwise.
# =====================================================================================
all_dependencies_built() {
    local ctid="$1"
    shift
    local built_ctids=("$@")
    local dependencies
    dependencies=$(jq_get_value "$ctid" ".dependencies // [] | .[]" || echo "")

    if [ -z "$dependencies" ]; then
        return 0
    fi

    for dep in $dependencies; do
        if ! [[ " ${built_ctids[*]} " =~ " ${dep} " ]]; then
            return 1
        fi
    done

    return 0
}

# =====================================================================================
# Function: is_clone_ready
# Description: Checks if a container that needs to be cloned is ready.
# Arguments:
#   $1 - CTID of the container to check.
#   $2 - Array of built CTIDs.
# Returns:
#   0 if the clone is ready, 1 otherwise.
# =====================================================================================
is_clone_ready() {
    local ctid="$1"
    shift
    local built_ctids=("$@")
    local clone_from_ctid
    clone_from_ctid=$(jq_get_value "$ctid" ".clone_from_ctid" || echo "")

    if [ -z "$clone_from_ctid" ]; then
        return 0
    fi

    if ! [[ " ${built_ctids[*]} " =~ " ${clone_from_ctid} " ]]; then
        return 1
    fi

    local source_snapshot_name
    source_snapshot_name=$(jq_get_value "$clone_from_ctid" ".template_snapshot_name")
    if ! pct listsnapshot "$clone_from_ctid" | grep -q "$source_snapshot_name"; then
        return 1
    fi

    return 0
}

# =====================================================================================
# Function: run_letsg_mode
# Description: Orchestrates the building of all containers based on dependencies.
# =====================================================================================
run_letsg_mode() {
    log_info "Starting LetsGo mode with dependency resolution..."
    local to_build
    to_build=($(jq -r '.lxc_configs | keys[]' "$LXC_CONFIG_FILE"))
    local built=()
    local build_progress=true

    while [ ${#to_build[@]} -gt 0 ] && [ "$build_progress" = true ]; do
        build_progress=false
        local remaining_builds=()
        for ctid in "${to_build[@]}"; do
            if all_dependencies_built "$ctid" "${built[@]}" && is_clone_ready "$ctid" "${built[@]}"; then
                log_info "Container $ctid is ready to build."
                if main_state_machine "$ctid"; then
                    built+=("$ctid")
                    build_progress=true
                else
                    log_fatal "Failed to build container $ctid. Aborting LetsGo mode."
                fi
            else
                remaining_builds+=("$ctid")
            fi
        done
        to_build=("${remaining_builds[@]}")
    done

    if [ ${#to_build[@]} -gt 0 ]; then
        log_fatal "Could not build all containers. Check for circular or missing dependencies. Remaining containers: ${to_build[*]}"
    fi

    log_info "LetsGo mode completed successfully."
}

# =====================================================================================
# Function: main
# Description: The main function of the script. It orchestrates the entire process
#              of setting up the hypervisor or creating and configuring containers.
# =====================================================================================
main() {
    setup_logging "$LOG_FILE"
    parse_arguments "$@"

    if [ "$DRY_RUN" = true ]; then
        log_info "Dry-run mode is enabled. No actual changes will be made."
    fi

    if [ "$SETUP_HYPERVISOR" = true ]; then
        setup_hypervisor "$VM_CONFIG_FILE"
    elif [ "$CREATE_VM" = true ]; then
        log_info "Starting VM creation for: $VM_NAME"
        create_vm "$VM_NAME"
        log_info "VM creation process for $VM_NAME completed."
        exit_script 0
    elif [ "$START_VM" = true ]; then
        log_info "Starting VM: $VM_ID"
        start_vm "$VM_ID"
        exit_script 0
    elif [ "$STOP_VM" = true ]; then
        log_info "Stopping VM: $VM_ID"
        stop_vm "$VM_ID"
        exit_script 0
    elif [ "$DELETE_VM" = true ]; then
        log_info "Deleting VM: $VM_ID"
        delete_vm "$VM_ID"
        exit_script 0
    elif [ "$SMOKE_TEST" = true ]; then
        run_smoke_tests
    elif [ "$LETSGO" = true ]; then
        run_letsg_mode
        exit_script 0
    fi

    for CTID in "${CTID_LIST[@]}"; do
        main_state_machine "$CTID"
    done
}

# =====================================================================================
# State Machine for Container Orchestration
# =====================================================================================
main_state_machine() {
    local CTID="$1"
    log_info "Starting state machine for CTID: $CTID"

    # Define the states in the order of execution
    local states=(
        "validate_inputs"
        "ensure_container_defined"
        "apply_configurations"
        "apply_zfs_volumes"
        "apply_dedicated_volumes"
        "ensure_container_disk_size"
        "start_container"
        "apply_features"
        "run_portainer_script"
        "run_application_script"
        "run_health_check"
        "create_pre_configured_snapshot"
        "run_post_deployment_validation"
        "create_final_form_snapshot"
        "create_template_snapshot"
    )

    # Execute each state function
    for state in "${states[@]}"; do
        log_info "Executing state: $state for CTID: $CTID"
        if ! "$state" "$CTID"; then
            log_fatal "State '$state' failed for CTID $CTID. Aborting."
        fi
    done

    log_info "Orchestration for CTID $CTID completed successfully."
}

# --- Main script execution ---
main "$@"