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
STATE_DIR="/var/lib/phoenix_hypervisor/state"
DRY_RUN=false # Flag for dry-run mode
LOG_FILE="/var/log/phoenix_hypervisor/orchestrator_$(date +%Y%m%d).log"

# =====================================================================================
# Function: run_pct_command
# Description: A robust wrapper for executing pct commands with error handling.
#              In dry-run mode, it logs the command instead of executing it.
# Arguments:
#   $@ - The arguments to pass to the 'pct' command.
# Returns:
#   0 on success, 1 on failure.
# =====================================================================================
run_pct_command() {
    local pct_args=("$@")
    log_info "Executing: pct ${pct_args[*]}"

    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN: Would execute 'pct ${pct_args[*]}'"
        return 0
    fi

    if ! pct "${pct_args[@]}"; then
        log_error "'pct ${pct_args[*]}' command failed."
        return 1
    fi
    log_info "'pct ${pct_args[*]}' command executed successfully."
    return 0
}

# =====================================================================================
# Function: jq_get_value
# Description: A robust wrapper for jq to query the LXC config file.
#              It retrieves a specific value from the JSON configuration for a given CTID.
# Arguments:
#   $1 (ctid) - The container ID.
#   $2 (jq_query) - The jq query string to execute.
# Returns:
#   The queried value on success, and a non-zero status code on failure.
# =====================================================================================
jq_get_value() {
    local ctid="$1"
    local jq_query="$2"
    local value

    value=$(jq -r --arg ctid "$ctid" ".lxc_configs[\$ctid | tostring] | ${jq_query}" "$LXC_CONFIG_FILE")

    if [ "$?" -ne 0 ]; then
        log_error "jq command failed for CTID $ctid with query '${jq_query}'."
        return 1
    elif [ -z "$value" ] || [ "$value" == "null" ]; then
        # This is not always an error, some fields are optional.
        # The calling function should handle empty values if they are not expected.
        return 1
    fi

    echo "$value"
    return 0
}

# =====================================================================================
# Function: get_container_state
# Description: Retrieves the current state of the container from its state file.
#              If the state file does not exist, it defaults to 'defined'.
# Returns:
#   The current state of the container as a string.
# =====================================================================================
get_container_state() {
    local state_file="${STATE_DIR}/${CTID}.state"
    if [ -f "$state_file" ]; then
        cat "$state_file"
    else
        echo "defined"
    fi
}

# =====================================================================================
# Function: set_container_state
# Description: Sets the state of the container by writing to its state file.
#              In dry-run mode, it logs the action instead of performing it.
# Arguments:
#   $1 (new_state) - The new state to set for the container.
# =====================================================================================
set_container_state() {
    local new_state="$1"
    local state_file="${STATE_DIR}/${CTID}.state"
    log_info "Setting state for CTID $CTID to: $new_state"

    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN: Would write '$new_state' to '$state_file'"
        return 0
    fi

    if ! echo "$new_state" > "$state_file"; then
        log_fatal "Failed to write state to $state_file."
    fi
}

# =====================================================================================
# Function: parse_arguments
# Description: Parses and validates the command-line arguments.
#              It expects a CTID and an optional --dry-run flag.
# Arguments:
#   $@ - The command-line arguments passed to the script.
# =====================================================================================
parse_arguments() {
    if [ "$#" -eq 0 ]; then
        log_error "Usage: $0 <CTID> [--dry-run]"
        exit_script 2
    fi

    for arg in "$@"; do
        case $arg in
            --dry-run)
            DRY_RUN=true
            shift
            ;;
            *)
            CTID="$arg"
            ;;
        esac
    done

    if [ -z "$CTID" ]; then
        log_error "Usage: $0 <CTID> [--dry-run]"
        exit_script 2
    fi

    log_info "Received CTID: $CTID"
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
# Function: ensure_state_directory_exists
# Description: Ensures the state directory exists. If not, it creates it.
#              In dry-run mode, it logs the creation action.
# =====================================================================================
ensure_state_directory_exists() {
    if [ ! -d "$STATE_DIR" ]; then
        log_info "State directory not found. Creating: $STATE_DIR"
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY-RUN: Would create directory '$STATE_DIR'"
            return 0
        fi
        if ! mkdir -p "$STATE_DIR"; then
            log_fatal "Failed to create state directory at $STATE_DIR."
        fi
    fi
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
    set_container_state "created"
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
    local features=$(jq_get_value "$CTID" ".features" || echo "")
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

    # --- Add optional features if they are defined ---
    if [ -n "$features" ]; then
        pct_create_cmd+=(--features "$features")
    fi

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
    set_container_state "configured"
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
    local features=$(jq_get_value "$CTID" ".features" || echo "")

    # --- Apply core settings ---
    run_pct_command set "$CTID" --memory "$memory_mb" || log_fatal "Failed to set memory."
    run_pct_command set "$CTID" --cores "$cores" || log_fatal "Failed to set cores."
    if [ -n "$features" ]; then
        run_pct_command set "$CTID" --features "$features" || log_fatal "Failed to set features."
    fi

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
    set_container_state "running"
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
    set_container_state "customizing"
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
    set_container_state "completed"
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
    validate_inputs
    ensure_state_directory_exists

    # --- State Machine ---
    local current_state
    current_state=$(get_container_state)
    log_info "Initial state for CTID $CTID is: $current_state"

    # The case statement uses fall-through (;&) to progress through the states
    # until the container is running or an error occurs.
    case "$current_state" in
        "defined")
            handle_defined_state
            current_state=$(get_container_state)
            ;&
        "created")
            handle_created_state
            current_state=$(get_container_state)
            ;&
        "configured")
            handle_configured_state
            current_state=$(get_container_state)
            ;&
        "running")
            handle_running_state
            current_state=$(get_container_state)
            ;&
        "customizing")
            handle_customizing_state
            current_state=$(get_container_state)
            ;&
        "completed")
            log_info "Container $CTID is in the 'completed' state. Orchestration finished."
            ;;
        *)
            log_fatal "Unknown state '$current_state' for CTID $CTID."
            ;;
    esac

    log_info "============================================================"
    log_info "Phoenix Orchestrator Finished"
    log_info "============================================================"
    exit_script 0
}

# --- Script Execution ---
# Call the main function with all command-line arguments.
main "$@"