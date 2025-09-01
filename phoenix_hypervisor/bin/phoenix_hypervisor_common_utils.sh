#!/bin/bash
#
# File: phoenix_hypervisor_common_utils.sh
# Description: Centralized environment and logging functions for all Phoenix Hypervisor scripts.
#              This script should be sourced by all other scripts to ensure a consistent
#              execution environment and standardized logging.
# Version: 1.0.0
# Author: Roo (AI Architect)

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Global Constants ---
export HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"
export LXC_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
export LXC_CONFIG_SCHEMA_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json"
export MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"

# --- Environment Setup ---
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export PATH="/usr/local/bin:$PATH" # Ensure /usr/local/bin is in PATH for globally installed npm packages like ajv-cli

# --- Logging Functions ---
log_debug() {
    if [ "$PHOENIX_DEBUG" == "true" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $(basename "$0"): $*" | tee -a "$MAIN_LOG_FILE"
    fi
}

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $(basename "$0"): $*" | tee -a "$MAIN_LOG_FILE"
}

log_warn() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $(basename "$0"): $*" | tee -a "$MAIN_LOG_FILE" >&2
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $(basename "$0"): $*" | tee -a "$MAIN_LOG_FILE" >&2
}

log_fatal() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [FATAL] $(basename "$0"): $*" | tee -a "$MAIN_LOG_FILE" >&2
    exit 1
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

# =====================================================================================
# Function: pct_exec
# Description: Executes a command inside an LXC container using 'pct exec'.
#              Handles errors and ensures commands are run with appropriate privileges.
# Arguments:
#   $1 (ctid) - The container ID.
#   $@ - The command and its arguments to execute inside the container.
# =====================================================================================
pct_exec() {
    local ctid="$1"
    shift # Remove ctid from the arguments list
    local cmd_args=("$@")

    log_info "Executing in CTID $ctid: ${cmd_args[*]}"
    if ! pct exec "$ctid" -- "${cmd_args[@]}"; then
        log_error "Command failed in CTID $ctid: '${cmd_args[*]}'"
        return 1
    fi
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
# Function: ensure_nvidia_repo_is_configured
# Description: Ensures the NVIDIA CUDA repository is configured in the container.
#              This function is idempotent and can be called safely multiple times.
# Arguments:
#   $1 (ctid) - The container ID.
# =====================================================================================
ensure_nvidia_repo_is_configured() {
    local ctid="$1"
    log_info "Ensuring NVIDIA CUDA repository is configured in CTID $ctid..."

    if pct_exec "$ctid" [ -f /etc/apt/sources.list.d/cuda.list ]; then
        log_info "NVIDIA CUDA repository already configured. Skipping."
        return 0
    fi

    local nvidia_repo_url=$(jq -r '.nvidia_repo_url' "$LXC_CONFIG_FILE")
    local cuda_pin_url="${nvidia_repo_url}cuda-ubuntu2404.pin"
    local cuda_key_url="${nvidia_repo_url}3bf863cc.pub"
    local cuda_keyring_path="/etc/apt/trusted.gpg.d/cuda-archive-keyring.gpg"

    pct_exec "$ctid" wget -qO /etc/apt/preferences.d/cuda-repository-pin-600 "$cuda_pin_url"
    pct_exec "$ctid" curl -fsSL "$cuda_key_url" | pct_exec "$ctid" gpg --dearmor -o "$cuda_keyring_path"
    pct_exec "$ctid" bash -c "echo \"deb [signed-by=${cuda_keyring_path}] ${nvidia_repo_url} /\" > /etc/apt/sources.list.d/cuda.list"
    pct_exec "$ctid" apt-get update
}

# --- Initial Environment Check (only run once per main script execution) ---
# This block ensures that the environment is initialized only when the script is run directly,
# not when sourced by other scripts.
if [[ "${BASH_SOURCE}" == "${0}" ]]; then
    # Initialize/Clear the main log file only if this is the main script execution
    > "$MAIN_LOG_FILE"
    log_info "Environment script initialized."
fi