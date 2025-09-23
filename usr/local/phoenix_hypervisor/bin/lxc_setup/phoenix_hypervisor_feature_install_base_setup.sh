#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_base_setup.sh
# Description: Automates the basic OS configuration for a new LXC container.
#              This script installs essential packages (curl, wget, vim, htop, jq, git,
#              rsync, s-tui, gnupg, locales) and sets the system locale to en_US.UTF-8.
#              It is designed to be idempotent and is typically called by the main orchestrator.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), dpkg, apt-get, grep, bash, locale-gen, update-locale.
# Inputs:
#   $1 (CTID) - The container ID for the LXC container to configure.
# Outputs:
#   Package installation logs, locale configuration output, log messages to stdout
#   and MAIN_LOG_FILE, exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Source common utilities ---
# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""

# =====================================================================================
# Function: parse_arguments
# Description: Parses the CTID from command-line arguments.
# =====================================================================================
# =====================================================================================
# Function: parse_arguments
# Description: Parses command-line arguments to extract the Container ID (CTID).
# Arguments:
#   $1 - The Container ID (CTID) for the LXC container.
# Returns:
#   Exits with status 2 if no CTID is provided.
# =====================================================================================
parse_arguments() {
    # Check if exactly one argument (CTID) is provided
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1" # Assign the first argument to CTID
    log_info "Executing Base Setup feature for CTID: $CTID"
}

# =====================================================================================
# Function: perform_base_os_setup
# Description: Installs essential packages and configures the OS.
# =====================================================================================
# =====================================================================================
# Function: perform_base_os_setup
# Description: Installs essential packages and configures the system locale within
#              the specified LXC container. It performs idempotency checks for
#              package installations and locale settings.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if package installation or locale configuration fails.
# =====================================================================================
perform_base_os_setup() {
    log_info "Performing base OS setup in CTID: $CTID"

    # --- Idempotency Check & Package Installation ---
    log_info "Checking for essential packages in CTID $CTID..."
    local essential_packages=("curl" "wget" "vim" "htop" "jq" "git" "rsync" "s-tui" "gnupg" "locales")
    local packages_to_install=()

    for pkg in "${essential_packages[@]}"; do
        if ! is_command_available "$CTID" "$pkg"; then
            packages_to_install+=("$pkg")
        fi
    done

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_info "Installing missing packages: ${packages_to_install[*]}"
        pct_exec "$CTID" apt-get update
        pct_exec "$CTID" apt-get install -y "${packages_to_install[@]}"
    else
        log_info "All essential packages are already installed."
    fi

    # --- Locale Configuration ---
    log_info "Configuring locale to en_US.UTF-8..."
    pct_exec "$CTID" sed -i 's/^# *\\(en_US.UTF-8\\)/\\1/' /etc/locale.gen
    pct_exec "$CTID" locale-gen en_US.UTF-8
    pct_exec "$CTID" update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
    log_info "Locale configuration complete."

    log_info "Base OS setup complete for CTID $CTID."
}

# =====================================================================================
# Function: main
# Description: Main entry point for the base setup feature script.
# =====================================================================================
# =====================================================================================
# Function: main
# Description: Main entry point for the base setup feature script.
#              It parses arguments, performs the base OS setup, and exits.
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   Exits with status 0 on successful completion.
# =====================================================================================
main() {
    parse_arguments "$@" # Parse command-line arguments
    if is_feature_installed "$CTID" "base_setup"; then
        log_info "Base setup feature is already installed. Skipping."
        exit_script 0
    fi
    perform_base_os_setup # Perform base OS setup
    exit_script 0 # Exit successfully
}

main "$@"