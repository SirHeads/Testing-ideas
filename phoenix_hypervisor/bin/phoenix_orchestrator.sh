#!/bin/bash
#
# File: phoenix_orchestrator.sh
# Description: Orchestrates the creation and cloning of LXC containers.
#              This script serves as the single point of entry for container provisioning.
#              It implements a state machine to ensure idempotent and resumable execution.
# Version: 2.1.0
# Author: Roo (AI Engineer)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "$(dirname "$0")/phoenix_hypervisor_common_utils.sh"

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
VM_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"
VM_CONFIG_SCHEMA_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.schema.json"




# =====================================================================================
# Function: parse_arguments
# Description: Parses and validates the command-line arguments.
#              It expects a CTID and an optional --dry-run flag.
# Arguments:
#   $@ - The command-line arguments passed to the script.
# =====================================================================================
parse_arguments() {
    if [ "$#" -eq 0 ]; then
        log_error "Usage: $0 [--create-vm <vm_name> | --start-vm <vm_id> | --stop-vm <vm_id> | --delete-vm <vm_id> | <CTID>] [--dry-run] | $0 --setup-hypervisor [--dry-run]"
        exit_script 2
    fi

    local operation_mode_set=false

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --setup-hypervisor)
                SETUP_HYPERVISOR=true
                operation_mode_set=true
                shift
                ;;
            --create-vm)
                CREATE_VM=true
                VM_NAME="$2"
                operation_mode_set=true
                shift 2
                ;;
            --start-vm)
                START_VM=true
                VM_ID="$2"
                operation_mode_set=true
                shift 2
                ;;
            --stop-vm)
                STOP_VM=true
                VM_ID="$2"
                operation_mode_set=true
                shift 2
                ;;
            --delete-vm)
                DELETE_VM=true
                VM_ID="$2"
                operation_mode_set=true
                shift 2
                ;;
            -*) # Unknown flags
                log_error "Unknown option: $1"
                exit_script 2
                ;;
            *) # Positional argument (CTID)
                if [ "$operation_mode_set" = true ]; then
                    log_fatal "Cannot combine CTID with other operation modes (--create-vm, --start-vm, etc.)."
                fi
                CTID="$1"
                operation_mode_set=true
                shift
                ;;
        esac
    done

    if [ "$operation_mode_set" = false ]; then
        log_fatal "Missing required arguments. Usage: $0 [--create-vm <vm_name> | --start-vm <vm_id> | --stop-vm <vm_id> | --delete-vm <vm_id> | <CTID>] [--dry-run] | $0 --setup-hypervisor [--dry-run]"
    fi

    if [ "$SETUP_HYPERVISOR" = true ]; then
        log_info "Hypervisor setup mode enabled."
    elif [ "$CREATE_VM" = true ]; then
        if [ -z "$VM_NAME" ]; then
            log_fatal "Missing VM name for --create-vm. Usage: $0 --create-vm <vm_name>"
        fi
        log_info "VM creation mode for VM: $VM_NAME"
    elif [ "$START_VM" = true ]; then
        if [ -z "$VM_ID" ]; then
            log_fatal "Missing VM ID for --start-vm. Usage: $0 --start-vm <vm_id>"
        fi
        log_info "VM start mode for VM ID: $VM_ID"
    elif [ "$STOP_VM" = true ]; then
        if [ -z "$VM_ID" ]; then
            log_fatal "Missing VM ID for --stop-vm. Usage: $0 --stop-vm <vm_id>"
        fi
        log_info "VM stop mode for VM ID: $VM_ID"
    elif [ "$DELETE_VM" = true ]; then
        if [ -z "$VM_ID" ]; then
            log_fatal "Missing VM ID for --delete-vm. Usage: $0 --delete-vm <vm_id>"
        fi
        log_info "VM delete mode for VM ID: $VM_ID"
    else
        if [ -z "$CTID" ]; then
            log_fatal "Missing CTID for container orchestration. Usage: $0 <CTID> [--dry-run]"
        fi
        log_info "Container orchestration mode for CTID: $CTID"
    fi

    if [ "$DRY_RUN" = true ]; then
        log_info "Dry-run mode enabled."
    fi
}

# =====================================================================================
# Function: validate_inputs
# Description: Validates the script's essential inputs, such as the presence of the
#              LXC config file and the validity of the CTID.
# =====================================================================================
validate_inputs() {
    log_info "Starting input validation..."
    if [ -z "$LXC_CONFIG_FILE" ]; then
        log_fatal "LXC_CONFIG_FILE environment variable is not set."
    fi
    log_info "LXC_CONFIG_FILE: $LXC_CONFIG_FILE"

    if [ ! -f "$LXC_CONFIG_FILE" ]; then
        log_fatal "LXC configuration file not found or not readable at $LXC_CONFIG_FILE."
    fi

    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_fatal "Invalid CTID '$CTID'. Must be a positive integer."
    fi

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
handle_defined_state() {
    log_info "Handling 'defined' state for CTID: $CTID"
    local clone_from_ctid
    clone_from_ctid=$(jq_get_value "$CTID" ".clone_from_ctid" || echo "")

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
create_container_from_template() {
    log_info "Starting creation of container $CTID from template."

    # --- Retrieve all necessary parameters from the config file ---
    local hostname=$(jq_get_value "$CTID" ".name")
    local memory_mb=$(jq_get_value "$CTID" ".memory_mb")
    local cores=$(jq_get_value "$CTID" ".cores")
    local template=$(jq_get_value "$CTID" ".template")
    local storage_pool=$(jq_get_value "$CTID" ".storage_pool")
    local storage_size_gb=$(jq_get_value "$CTID" ".storage_size_gb")
    local features=$(jq_get_value "$CTID" ".features | join(\",\")" || echo "")
    local mac_address=$(jq_get_value "$CTID" ".mac_address")
    local unprivileged_bool=$(jq_get_value "$CTID" ".unprivileged")
    local unprivileged_val=$([ "$unprivileged_bool" == "true" ] && echo "1" || echo "0")

    # --- Construct network configuration string ---
    local net0_name=$(jq_get_value "$CTID" ".network_config.name")
    local net0_bridge=$(jq_get_value "$CTID" ".network_config.bridge")
    local net0_ip=$(jq_get_value "$CTID" ".network_config.ip")
    local net0_gw=$(jq_get_value "$CTID" ".network_config.gw")
    local net0_string="name=${net0_name},bridge=${net0_bridge},ip=${net0_ip},gw=${net0_gw},hwaddr=${mac_address}"

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

    # --- The --features flag is reserved for Proxmox's internal use. ---
    # --- Custom features are handled by the state machine after creation. ---

    # --- Execute the command ---
    if ! run_pct_command "${pct_create_cmd[@]}"; then
        log_fatal "'pct create' command failed for CTID $CTID."
    fi
    log_info "Container $CTID created from template successfully."
}

# =====================================================================================
# Function: clone_container
# Description: Clones an LXC container from a source container and a specific snapshot.
# =====================================================================================
clone_container() {
    local source_ctid=$(jq_get_value "$CTID" ".clone_from_ctid")
    log_info "Starting clone of container $CTID from source CTID $source_ctid."

    local source_snapshot_name=$(jq_get_value "$source_ctid" ".template_snapshot_name")

    # --- Pre-flight checks for cloning ---
    if ! pct status "$source_ctid" > /dev/null 2>&1; then
        log_fatal "Source container $source_ctid does not exist."
    fi
    if ! pct listsnapshot "$source_ctid" | grep -q "$source_snapshot_name"; then
        log_fatal "Snapshot '$source_snapshot_name' not found on source container $source_ctid."
    fi

    local hostname=$(jq_get_value "$CTID" ".name")
    local storage_pool=$(jq_get_value "$CTID" ".storage_pool")

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
# Function: handle_created_state
# Description: Handles the 'created' state by applying configurations.
# =====================================================================================
handle_created_state() {
    log_info "Handling 'created' state for CTID: $CTID"
    apply_configurations
}

# =====================================================================================
# Function: apply_configurations
# Description: Applies configurations to a newly created or cloned container, such as
#              memory, cores, features, and network settings.
# =====================================================================================
apply_configurations() {
    log_info "Applying configurations for CTID: $CTID"

    # --- Retrieve configuration values ---
    local memory_mb=$(jq_get_value "$CTID" ".memory_mb")
    local cores=$(jq_get_value "$CTID" ".cores")
    local features=$(jq_get_value "$CTID" ".features[]" || echo "")

    # --- Apply core settings ---
    run_pct_command set "$CTID" --memory "$memory_mb" || log_fatal "Failed to set memory."
    run_pct_command set "$CTID" --cores "$cores" || log_fatal "Failed to set cores."

    # --- Enable Nesting for Docker ---
    if [[ " ${features[*]} " =~ " docker " ]]; then
        log_info "Docker feature detected. Enabling nesting for CTID $CTID..."
        run_pct_command set "$CTID" --features nesting=1 || log_fatal "Failed to enable nesting."
    fi
    # --- The --features flag is reserved for Proxmox's internal use. ---
    # --- Custom features are handled by the state machine after creation. ---

    # --- Apply network settings ---
    local net0_name=$(jq_get_value "$CTID" ".network_config.name")
    local net0_bridge=$(jq_get_value "$CTID" ".network_config.bridge")
    local net0_ip=$(jq_get_value "$CTID" ".network_config.ip")
    local net0_gw=$(jq_get_value "$CTID" ".network_config.gw")
    local mac_address=$(jq_get_value "$CTID" ".mac_address")
    local net0_string="name=${net0_name},bridge=${net0_bridge},ip=${net0_ip},gw=${net0_gw},hwaddr=${mac_address}"

    run_pct_command set "$CTID" --net0 "$net0_string" || log_fatal "Failed to set network configuration."
    log_info "Configurations applied successfully for CTID $CTID."
}

# =====================================================================================
# Function: handle_configured_state
# Description: Handles the 'configured' state by starting the container.
# =====================================================================================
handle_configured_state() {
    log_info "Handling 'configured' state for CTID: $CTID"
    start_container
}

# =====================================================================================
# Function: start_container
# Description: Starts the container with retry logic to handle transient issues.
# =====================================================================================
start_container() {
    log_info "Attempting to start container CTID: $CTID with retries..."
    local attempts=0
    local max_attempts=3
    local interval=5 # seconds

    while [ "$attempts" -lt "$max_attempts" ]; do
        if run_pct_command start "$CTID"; then
            log_info "Container $CTID started successfully."
            return 0
        else
            attempts=$((attempts + 1))
            log_error "WARNING: 'pct start' command failed for CTID $CTID (Attempt $attempts/$max_attempts)."
            if [ "$attempts" -lt "$max_attempts" ]; then
                log_info "Retrying in $interval seconds..."
                sleep "$interval"
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
handle_running_state() {
    log_info "Handling 'running' state for CTID: $CTID"
    apply_features
}

# =====================================================================================
# Function: apply_features
# Description: Applies a series of feature scripts to the container based on its
#              configuration in the JSON file.
# =====================================================================================
apply_features() {
    log_info "Applying features for CTID: $CTID"
    local features
    features=$(jq_get_value "$CTID" ".features[]" || echo "")

    if [ -z "$features" ]; then
        log_info "No features to apply for CTID $CTID."
        return 0
    fi

    for feature in $features; do
        local feature_script_path="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_feature_install_${feature}.sh"
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
# Function: handle_customizing_state
# Description: Handles the 'customizing' state. This is the final state after
#              all features have been applied.
# =====================================================================================
handle_customizing_state() {
    log_info "Container $CTID has been fully customized."
    run_application_script
}

# =====================================================================================
# Function: run_application_script
# Description: Executes a final application script for the container if one is defined
#              in the configuration.
# =====================================================================================
run_application_script() {
    log_info "Checking for application script for CTID: $CTID"
    local app_script_name
    app_script_name=$(jq_get_value "$CTID" ".application_script" || echo "")

    if [ -z "$app_script_name" ]; then
        log_info "No application script to run for CTID $CTID."
        return 0
    fi

    local app_script_path="/usr/local/phoenix_hypervisor/bin/${app_script_name}"
    log_info "Executing application script: $app_script_name ($app_script_path)"

    if [ ! -f "$app_script_path" ]; then
        log_fatal "Application script not found at $app_script_path."
    fi

    if ! "$app_script_path" "$CTID"; then
        log_fatal "Application script '$app_script_name' failed for CTID $CTID."
    fi

    log_info "Application script executed successfully for CTID $CTID."
}

# =====================================================================================
# Function: create_template_snapshot
# Description: Creates a snapshot of a container if it is designated as a template
#              in the configuration file.
# =====================================================================================
create_template_snapshot() {
    log_info "Checking for template snapshot for CTID: $CTID"
    local snapshot_name
    snapshot_name=$(jq_get_value "$CTID" ".template_snapshot_name" || echo "")

    if [ -z "$snapshot_name" ]; then
        log_info "No template snapshot defined for CTID $CTID. Skipping."
        return 0
    fi

    if pct listsnapshot "$CTID" | grep -q "$snapshot_name"; then
        log_info "Snapshot '$snapshot_name' already exists for CTID $CTID. Skipping."
        return 0
    fi

    log_info "Creating snapshot '$snapshot_name' for template container $CTID..."
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
run_qm_command() {
    local cmd_description="qm $*"
    log_info "Executing: $cmd_description"
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry-run: Skipping actual command execution."
        return 0
    fi
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
create_vm() {
    local vm_name="$1"
    log_info "Attempting to create VM: $vm_name"

    # 1. Parse Configuration
    local vm_config
    vm_config=$(jq ".vms[] | select(.name == \"$vm_name\")" "$VM_CONFIG_FILE")

    if [ -z "$vm_config" ]; then
        log_fatal "VM configuration for '$vm_name' not found in $VM_CONFIG_FILE."
    fi

    # 2. Apply Defaults
    local vm_defaults
    vm_defaults=$(jq ".vm_defaults" "$VM_CONFIG_FILE")

    local template=$(echo "$vm_config" | jq -r ".template // \"$(echo "$vm_defaults" | jq -r ".template")\"")
    local cores=$(echo "$vm_config" | jq -r ".cores // $(echo "$vm_defaults" | jq -r ".cores")")
    local memory_mb=$(echo "$vm_config" | jq -r ".memory_mb // $(echo "$vm_defaults" | jq -r ".memory_mb")")
    local disk_size_gb=$(echo "$vm_config" | jq -r ".disk_size_gb // $(echo "$vm_defaults" | jq -r ".disk_size_gb")")
    local storage_pool=$(echo "$vm_config" | jq -r ".storage_pool // \"$(echo "$vm_defaults" | jq -r ".storage_pool")\"")
    local network_bridge=$(echo "$vm_config" | jq -r ".network_bridge // \"$(echo "$vm_defaults" | jq -r ".network_bridge")\"")
    local post_create_scripts=$(echo "$vm_config" | jq -c ".post_create_scripts // []")

    # Generate a unique VM ID (e.g., starting from 9000 and finding the next available)
    local vm_id=9000
    while qm status "$vm_id" > /dev/null 2>&1; do
        vm_id=$((vm_id + 1))
    done
    log_info "Assigned VM ID: $vm_id"

    # 3. Create VM
    log_info "Creating VM $vm_name (ID: $vm_id) from template $template..."
    local qm_create_cmd=(
        qm create "$vm_id"
        --name "$vm_name"
        --memory "$memory_mb"
        --cores "$cores"
        --net0 "virtio,bridge=${network_bridge}"
        --ostype "l26" # Assuming Linux 2.6+ kernel
        --scsi0 "${storage_pool}:${disk_size_gb},import-from=${template}"
    )

    if ! run_qm_command "${qm_create_cmd[@]}"; then
        log_fatal "'qm create' command failed for VM $vm_name (ID: $vm_id)."
    fi

    # Set boot order
    log_info "Setting boot order for VM $vm_id..."
    if ! run_qm_command set "$vm_id" --boot "order=scsi0"; then
        log_fatal "'qm set boot order' command failed for VM $vm_id."
    fi

    log_info "VM $vm_name (ID: $vm_id) created successfully."

    # 4. Post-Creation Setup
    if [ "$(echo "$post_create_scripts" | jq 'length')" -gt 0 ]; then
        log_info "Executing post-creation scripts for VM $vm_name (ID: $vm_id)..."
        # Start the VM to run post-creation scripts
        start_vm "$vm_id"

        # Wait for VM to boot and get an IP address (simplified, can be improved)
        log_info "Waiting for VM $vm_id to boot and acquire an IP address..."
        sleep 30 # Adjust as needed

        for script in $(echo "$post_create_scripts" | jq -r '.[]'); do
            local script_path="$(dirname "$0")/bin/${script}" # Assuming scripts are in this path
            log_info "Executing post-create script: $script for VM $vm_id"
            if [ ! -f "$script_path" ]; then
                log_fatal "Post-create script not found at $script_path."
            fi
            # This assumes the script can be run remotely, e.g., via SSH or qm agent
            # For simplicity, we'll just log its execution here.
            # In a real scenario, you'd use `qm agent exec` or SSH.
            log_info "Simulating execution of $script inside VM $vm_id."
            # Example: qm agent "$vm_id" exec -- "$script_path"
            if ! "$script_path" "$vm_id"; then # Passing VM_ID to the script
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
start_vm() {
    local vm_id="$1"
    log_info "Attempting to start VM ID: $vm_id"

    if ! qm status "$vm_id" > /dev/null 2>&1; then
        log_fatal "VM ID $vm_id does not exist."
    fi

    if qm status "$vm_id" | grep -q "running"; then
        log_info "VM ID $vm_id is already running."
        return 0
    fi

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
stop_vm() {
    local vm_id="$1"
    log_info "Attempting to stop VM ID: $vm_id"

    if ! qm status "$vm_id" > /dev/null 2>&1; then
        log_fatal "VM ID $vm_id does not exist."
    fi

    if qm status "$vm_id" | grep -q "stopped"; then
        log_info "VM ID $vm_id is already stopped."
        return 0
    fi

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
delete_vm() {
    local vm_id="$1"
    log_info "Attempting to delete VM ID: $vm_id"

    if ! qm status "$vm_id" > /dev/null 2>&1; then
        log_info "VM ID $vm_id does not exist. Nothing to delete."
        return 0
    fi

    # Ensure VM is stopped before deleting
    if qm status "$vm_id" | grep -q "running"; then
        log_info "VM ID $vm_id is running. Attempting to stop before deletion."
        stop_vm "$vm_id"
    fi

    if ! run_qm_command destroy "$vm_id"; then
        log_fatal "'qm destroy' command failed for VM ID $vm_id."
    fi
    log_info "VM ID $vm_id deleted successfully."
}

# =====================================================================================
# Function: handle_hypervisor_setup_state
# Description: Orchestrates the execution of hypervisor setup scripts.
# =====================================================================================
handle_hypervisor_setup_state() {
    log_info "Starting hypervisor setup orchestration."

    # 1. Read and validate hypervisor_config.json
    log_info "Reading and validating hypervisor configuration from $HYPERVISOR_CONFIG_FILE..."
    if [ ! -f "$HYPERVISOR_CONFIG_FILE" ]; then
        log_fatal "Hypervisor configuration file not found at $HYPERVISOR_CONFIG_FILE."
    fi
    if [ ! -f "$HYPERVISOR_CONFIG_SCHEMA_FILE" ]; then
        log_fatal "Hypervisor configuration schema file not found at $HYPERVISOR_CONFIG_SCHEMA_FILE."
    fi

    if ! ajv validate -s "$HYPERVISOR_CONFIG_SCHEMA_FILE" -d "$HYPERVISOR_CONFIG_FILE"; then
        log_fatal "Hypervisor configuration validation failed. Please check $HYPERVISOR_CONFIG_FILE against $HYPERVISOR_CONFIG_SCHEMA_FILE."
    fi
    log_info "Hypervisor configuration validated successfully."

    # 2. Execute hypervisor feature scripts in sequence
    log_info "Executing hypervisor setup feature scripts..."

    local hypervisor_scripts=(
        "hypervisor_initial_setup.sh"
        "hypervisor_feature_install_nvidia.sh"
        "hypervisor_feature_create_admin_user.sh"
        "hypervisor_feature_setup_zfs.sh"
        "hypervisor_feature_setup_nfs.sh"
        "hypervisor_feature_setup_samba.sh"
    )

    for script_name in "${hypervisor_scripts[@]}"; do
        local script_path="$(dirname "$0")/hypervisor_setup/$script_name"
        log_info "Executing hypervisor script: $script_name"

        if [ ! -f "$script_path" ]; then
            log_fatal "Hypervisor setup script not found at $script_path."
        fi

        if ! "$script_path"; then
            log_fatal "Hypervisor setup script '$script_name' failed."
        fi
    done

    log_info "All hypervisor setup scripts executed successfully."
}

# =====================================================================================
# Function: setup_logging
# Description: Sets up the logging by creating the log directory and file.
# =====================================================================================
setup_logging() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [ ! -d "$log_dir" ]; then
        if ! mkdir -p "$log_dir"; then
            echo "FATAL: Failed to create log directory at $log_dir." >&2
            exit 1
        fi
    fi
    if ! touch "$LOG_FILE"; then
        echo "FATAL: Failed to create log file at $LOG_FILE." >&2
        exit 1
    fi
}

# =====================================================================================
# Function: main
# Description: The main entry point for the script. It orchestrates the entire
#              container provisioning process through a state machine.
# =====================================================================================
main() {
    # --- Initial Setup ---
    setup_logging
    exec &> >(tee -a "$LOG_FILE") # Redirect stdout/stderr to screen and log file

    log_info "============================================================"
    log_info "Phoenix Orchestrator Started"
    log_info "============================================================"

    parse_arguments "$@"

    if [ "$SETUP_HYPERVISOR" = true ]; then
        handle_hypervisor_setup_state
    elif [ "$CREATE_VM" = true ]; then
        create_vm "$VM_NAME"
    elif [ "$START_VM" = true ]; then
        start_vm "$VM_ID"
    elif [ "$STOP_VM" = true ]; then
        stop_vm "$VM_ID"
    elif [ "$DELETE_VM" = true ]; then
        delete_vm "$VM_ID"
    else
        validate_inputs
        # --- Stateless Orchestration Workflow for LXC Containers ---
        log_info "Starting stateless orchestration for CTID $CTID..."

        # 1. Ensure Container Exists
        if ! pct status "$CTID" > /dev/null 2>&1; then
            log_info "Container $CTID does not exist. Proceeding with creation..."
            handle_defined_state
        else
            log_info "Container $CTID already exists. Skipping creation."
        fi

        # 2. Ensure Container is Configured
        # The apply_configurations function is idempotent and can be run safely.
        log_info "Ensuring container $CTID is correctly configured..."
        apply_configurations

        # 3. Ensure Container is Running
        if ! pct status "$CTID" | grep -q "running"; then
            log_info "Container $CTID is not running. Attempting to start..."
            start_container
        else
            log_info "Container $CTID is already running."
        fi

        # 4. Apply Features
        # The feature scripts are designed to be idempotent.
        log_info "Applying all features to container $CTID..."
        apply_features

        # 5. Run Application Script
        # The application script should also be idempotent.
        log_info "Executing application script for container $CTID..."
        run_application_script

        # 6. Create Template Snapshot
        # If the container is a template, create a snapshot.
        create_template_snapshot

        log_info "Stateless orchestration for CTID $CTID completed."
    fi

    log_info "============================================================"
    log_info "Phoenix Orchestrator Finished"
    log_info "============================================================"
    exit_script 0
}

# --- Script Execution ---
# Call the main function with all command-line arguments.
main "$@"