#!/bin/bash
#
# File: phoenix_hypervisor_common_utils.sh
# Description: Centralized environment and logging functions for all Phoenix Hypervisor scripts.
#              This script should be sourced by all other scripts to ensure a consistent
#              execution environment and standardized logging.
# Version: 1.0.0
# Author: Roo (AI Architect)

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

# --- Initial Environment Check (only run once per main script execution) ---
# This block ensures that the environment is initialized only when the script is run directly,
# not when sourced by other scripts.
if [[ "${BASH_SOURCE}" == "${0}" ]]; then
    # Initialize/Clear the main log file only if this is the main script execution
    > "$MAIN_LOG_FILE"
    log_info "Environment script initialized."
fi