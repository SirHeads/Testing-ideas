#!/bin/bash
#
# File: phoenix_hypervisor_create_lxc.sh
# Description: Creates a single LXC container on the Proxmox host based on a specific
#              configuration block from `phoenix_lxc_configs.json`. This script
#              automates the `pct create` command, ensuring idempotent container
#              provisioning. Comments are optimized for Retrieval Augmented Generation (RAG),
#              facilitating effective chunking and vector database indexing.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script is a foundational component of the Phoenix Hypervisor, used for
# establishing new LXC containers, particularly base templates. It ensures that
# containers are created with predefined resources and network settings.
#
# Usage:
#   LXC_CONFIG_FILE="/path/to/phoenix_lxc_configs.json" ./phoenix_hypervisor_create_lxc.sh <CTID>
#
# Arguments:
#   - CTID (integer): The Container ID for the new LXC container to be created.
#
# Requirements:
#   - Proxmox VE host environment with `pct` command available.
#   - `jq` for robust JSON parsing.
#   - Access to Proxmox host and defined storage paths.
#   - The `LXC_CONFIG_FILE` environment variable must be set and point to a valid
#     `phoenix_lxc_configs.json` file.
#   - Appropriate permissions to manage LXC containers.
#
# Exit Codes:
#   0: Success (Container created and started successfully, or already existed)
#   1: General error
#   2: Invalid input arguments or configuration file issues
#   3: Container creation failed
#   4: Container start failed

# --- Global Variables and Constants ---
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"
# LXC_CONFIG_FILE will be set via environment variable by the orchestrator

# --- Logging Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] phoenix_hypervisor_create_lxc.sh: $*" | tee -a "$MAIN_LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] phoenix_hypervisor_create_lxc.sh: $*" | tee -a "$MAIN_LOG_FILE" >&2
}

# --- Exit Function ---
exit_script() {
    local exit_code=$1
    if [ "$exit_code" -eq 0 ]; then
        log_info "Script completed successfully."
    else
        log_error "Script failed with exit code $exit_code."
    fi
    exit "$exit_code"
}

# --- Script Variables ---
CTID=""
CONFIG_BLOCK_JSON=""
PCT_CREATE_CMD=""

# =====================================================================================
# Function: parse_arguments
# Description: Parses and validates the command-line arguments provided to the script.
#              It expects exactly one argument: the Container ID (CTID) for the LXC.
#
# Parameters:
#   - $@: All command-line arguments.
#
# Global Variables Modified:
#   - `CTID`: Stores the Container ID extracted from the arguments.
#
# Exit Conditions:
#   - Exits with code 2 if an incorrect number of arguments is provided.
#
# RAG Keywords: argument parsing, command-line interface, script input, CTID.
# =====================================================================================
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Received CTID: $CTID"
}

# =====================================================================================
# Function: validate_inputs
# Description: Validates the script's essential inputs, including the presence and
#              accessibility of the `LXC_CONFIG_FILE` environment variable and the
#              validity of the provided Container ID (CTID).
#
# Parameters: None (operates on global script variables)
#
# Global Variables Accessed:
#   - `LXC_CONFIG_FILE`: Path to the LXC configuration file.
#   - `CTID`: The Container ID to be validated.
#
# Exit Conditions:
#   - Exits with code 2 if `LXC_CONFIG_FILE` is not set, not found, unreadable,
#     or if `CTID` is not a valid positive integer.
#
# RAG Keywords: input validation, environment variable, configuration file,
#               CTID validation, error handling, script robustness.
# =====================================================================================
# =====================================================================================
validate_inputs() {
    if [ -z "$LXC_CONFIG_FILE" ]; then
        log_error "FATAL: LXC_CONFIG_FILE environment variable is not set."
        exit_script 2
    fi
    log_info "LXC_CONFIG_FILE: $LXC_CONFIG_FILE"

    if [ ! -f "$LXC_CONFIG_FILE" ]; then
        log_error "FATAL: LXC configuration file not found or not readable at $LXC_CONFIG_FILE."
        exit_script 2
    fi

    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_error "FATAL: Invalid CTID '$CTID'. Must be a positive integer."
        exit_script 2
    fi
    log_info "Input validation passed."
}

# =====================================================================================
# Function: check_container_exists
# Description: Checks if an LXC container with the specified CTID already exists
#              on the Proxmox host. This function is crucial for ensuring idempotency,
#              preventing the script from attempting to create an already existing container.
#
# Parameters: None (operates on global script variable `CTID`)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct status`).
#
# Exit Conditions:
#   - Exits with code 0 if the container already exists, indicating no further creation is needed.
#   - Continues execution if the container does not exist.
#
# RAG Keywords: container existence check, idempotency, LXC status, Proxmox `pct`, CTID.
# =====================================================================================
# =====================================================================================
check_container_exists() {
    log_info "Checking for existence of container CTID: $CTID"
    if pct status "$CTID" > /dev/null 2>&1; then
        log_info "Container $CTID already exists. Skipping creation."
        exit_script 0 # Exit successfully as container already exists
    else
        log_info "Container $CTID does not exist. Proceeding with creation."
    fi
}

# =====================================================================================
# Function: load_and_parse_config
# Description: Loads and parses the specific configuration block for the target CTID
#              from the main `phoenix_lxc_configs.json` file. This function is critical
#              for retrieving all necessary parameters to create the LXC container.
#
# Parameters: None (operates on global script variables `CTID` and `LXC_CONFIG_FILE`)
#
# Global Variables Modified:
#   - `CONFIG_BLOCK_JSON`: Stores the extracted JSON configuration string for the CTID.
#
# Dependencies:
#   - `jq`: Used for extracting the specific configuration block.
#
# Exit Conditions:
#   - Exits with code 2 if the configuration for the specified CTID is not found
#     or is invalid in `LXC_CONFIG_FILE`.
#
# RAG Keywords: configuration loading, JSON parsing, LXC config block, CTID-specific settings.
# =====================================================================================
# =====================================================================================
load_and_parse_config() {
    log_info "Loading configuration for container $CTID from $LXC_CONFIG_FILE"
    CONFIG_BLOCK_JSON=$(jq -r --arg ctid "$CTID" '.lxc_configs[$ctid | tostring]' "$LXC_CONFIG_FILE")

    if [ "$CONFIG_BLOCK_JSON" == "null" ] || [ -z "$CONFIG_BLOCK_JSON" ]; then
        log_error "FATAL: Configuration for CTID $CTID not found in $LXC_CONFIG_FILE."
        exit_script 2
    fi
    log_info "Configuration block for CTID $CTID extracted successfully."
    # log_info "Config block: $CONFIG_BLOCK_JSON" # For debugging, can be verbose
}

# =====================================================================================
# Function: construct_pct_create_command
# Description: Dynamically builds the `pct create` command array based on the provided
#              CTID and the parsed configuration block (`CONFIG_BLOCK_JSON`). This
#              includes setting essential parameters like hostname, memory, cores,
#              template, storage, root filesystem size, network configuration (`net0`),
#              features, MAC address, and unprivileged status.
#
# Parameters: None (operates on global script variables `CTID` and `CONFIG_BLOCK_JSON`)
#
# Global Variables Modified:
#   - `PCT_CREATE_CMD`: An array storing the constructed `pct create` command and its arguments.
#
# Dependencies:
#   - `jq`: Used for extracting configuration values from `CONFIG_BLOCK_JSON`.
#
# RAG Keywords: `pct create` command, LXC container creation, command construction,
#               container resources, network configuration, Proxmox CLI, JSON parsing.
# =====================================================================================
# =====================================================================================
construct_pct_create_command() {
    log_info "Constructing pct create command for CTID: $CTID"

    local hostname=$(jq -r '.name' <<< "$CONFIG_BLOCK_JSON")
    local memory_mb=$(jq -r '.memory_mb' <<< "$CONFIG_BLOCK_JSON")
    local cores=$(jq -r '.cores' <<< "$CONFIG_BLOCK_JSON")
    local template=$(jq -r '.template' <<< "$CONFIG_BLOCK_JSON")
    local storage_pool=$(jq -r '.storage_pool' <<< "$CONFIG_BLOCK_JSON")
    local storage_size_gb=$(jq -r '.storage_size_gb' <<< "$CONFIG_BLOCK_JSON")
    local features=$(jq -r '.features' <<< "$CONFIG_BLOCK_JSON")
    local mac_address=$(jq -r '.mac_address' <<< "$CONFIG_BLOCK_JSON")
    local unprivileged_bool=$(jq -r '.unprivileged' <<< "$CONFIG_BLOCK_JSON")
    local unprivileged_val=$([ "$unprivileged_bool" == "true" ] && echo "1" || echo "0")

    local net0_name=$(jq -r '.network_config.name' <<< "$CONFIG_BLOCK_JSON")
    local net0_bridge=$(jq -r '.network_config.bridge' <<< "$CONFIG_BLOCK_JSON")
    local net0_ip=$(jq -r '.network_config.ip' <<< "$CONFIG_BLOCK_JSON")
    local net0_gw=$(jq -r '.network_config.gw' <<< "$CONFIG_BLOCK_JSON")
    local net0_string="name=${net0_name},bridge=${net0_bridge},ip=${net0_ip},gw=${net0_gw},hwaddr=${mac_address}"

    PCT_CREATE_CMD=(
        pct create "$CTID" "$template"
        --hostname "$hostname"
        --memory "$memory_mb"
        --cores "$cores"
        --storage "$storage_pool"
        --rootfs "${storage_pool}:${storage_size_gb}"
        --net0 "$net0_string"
    )

    if [ -n "$features" ] && [ "$features" != "null" ]; then
        PCT_CREATE_CMD+=(--features "$features")
    fi

    PCT_CREATE_CMD+=(--unprivileged "$unprivileged_val")
    log_info "Constructed pct create command: ${PCT_CREATE_CMD[*]}"
}

# =====================================================================================
# Function: execute_pct_create
# Description: Executes the pre-constructed `pct create` command to provision the new
#              LXC container. It captures and handles the command's exit status,
#              logging any failures.
#
# Parameters: None (operates on global script variable `PCT_CREATE_CMD`)
#
# Dependencies:
#   - `PCT_CREATE_CMD`: Must be populated by `construct_pct_create_command()`.
#
# Exit Conditions:
#   - Exits with code 3 if the `pct create` command fails.
#
# RAG Keywords: `pct create` execution, LXC container provisioning, command execution,
#               error handling, Proxmox CLI.
# =====================================================================================
# =====================================================================================
execute_pct_create() {
    log_info "Executing pct create command for CTID: $CTID"
    if ! "${PCT_CREATE_CMD[@]}"; then
        log_error "FATAL: 'pct create' command failed for CTID $CTID. Command: ${PCT_CREATE_CMD[*]}"
        exit_script 3
    fi
    log_info "'pct create' command executed successfully for CTID $CTID."
}

# =====================================================================================
# Function: start_container
# Description: Initiates the startup of the newly created LXC container using `pct start`.
#              This function ensures the container transitions to a running state.
#
# Parameters: None (operates on global script variable `CTID`)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct start`).
#
# Exit Conditions:
#   - Exits with code 4 if the `pct start` command fails.
#
# RAG Keywords: LXC container startup, Proxmox `pct start`, container management, error handling.
# =====================================================================================
# =====================================================================================
start_container() {
    log_info "Attempting to start container CTID: $CTID with retries..."
    local attempts=0
    local max_attempts=3
    local interval=5 # seconds

    while [ "$attempts" -lt "$max_attempts" ]; do
        if pct start "$CTID"; then
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

    log_error "FATAL: Container $CTID failed to start after $max_attempts attempts."
    exit_script 4
}

# =====================================================================================
# Function: main
# Description: The main entry point for the LXC container creation script.
#              It orchestrates the entire creation process by parsing arguments,
#              validating inputs, checking for existing containers, loading configurations,
#              constructing and executing the `pct create` command, and finally
#              starting the newly provisioned container.
#
# Parameters: None (operates on command-line arguments)
#
# Dependencies:
#   - `parse_arguments()`
#   - `validate_inputs()`
#   - `check_container_exists()`
#   - `load_and_parse_config()`
#   - `construct_pct_create_command()`
#   - `execute_pct_create()`
#   - `start_container()`
#   - `exit_script()`
#
# RAG Keywords: main function, script entry point, LXC creation flow, Proxmox automation.
# =====================================================================================
# =====================================================================================
main() {
    parse_arguments "$@"
    validate_inputs
    check_container_exists # This function will exit_script 0 if container already exists

    load_and_parse_config
    construct_pct_create_command
    execute_pct_create
    start_container

    exit_script 0
}

# Call the main function
main "$@"