#!/bin/bash
#
# File: feature_base_setup.sh
# Description: This feature script automates the basic OS configuration for a new
#              LXC container. It installs essential packages and sets the system locale.
#              It is designed to be called by the main orchestrator and is fully idempotent.
# Version: 1.0.0
# Author: Roo (AI Engineer)

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Source common utilities ---
source "$(dirname "$0")/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""

# =====================================================================================
# Function: parse_arguments
# Description: Parses the CTID from command-line arguments.
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Executing Base Setup feature for CTID: $CTID"
}

# =====================================================================================
# Function: perform_base_os_setup
# Description: Installs essential packages and configures the OS.
# =====================================================================================
perform_base_os_setup() {
    log_info "Performing base OS setup in CTID: $CTID"

    # --- Idempotency Check & Package Installation ---
    log_info "Checking for essential packages in CTID $CTID..."
    local essential_packages=("curl" "wget" "vim" "htop" "jq" "git" "rsync" "s-tui" "gnupg" "locales")
    local packages_to_install=()

    for pkg in "${essential_packages[@]}"; do
        if ! pct_exec "$CTID" dpkg -l | grep -q " ${pkg} "; then
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

    # --- Idempotency Check for Locale ---
    if pct_exec "$CTID" locale | grep -q "LANG=en_US.UTF-8"; then
        log_info "Locale is already correctly set."
    else
        log_info "Configuring locale..."
        pct_exec "$CTID" bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
        pct_exec "$CTID" locale-gen
        pct_exec "$CTID" update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
    fi

    log_info "Base OS setup complete for CTID $CTID."
}

# =====================================================================================
# Function: main
# Description: Main entry point for the base setup feature script.
# =====================================================================================
main() {
    parse_arguments "$@"
    perform_base_os_setup
    exit_script 0
}

main "$@"