#!/bin/bash

# -----------------------------------------------------------------------------
# Script: hypervisor_feature_set_heads_password.sh
# Description: Sets the password for the 'heads' user interactively.
#
# Usage:
#   sudo ./hypervisor_feature_set_heads_password.sh
#
# -----------------------------------------------------------------------------

# Source common utilities
# The script is in bin/hypervisor_setup, so we go up one level to bin
UTILS_PATH=$(dirname "$0")/../phoenix_hypervisor_common_utils.sh
if [ ! -f "$UTILS_PATH" ]; then
    echo "Fatal: Common utilities script not found at $UTILS_PATH"
    exit 1
fi
# shellcheck source=../phoenix_hypervisor_common_utils.sh
source "$UTILS_PATH"

# --- Main Function ---
main() {
    log_info "Starting 'heads' user password setting script."

    # Ensure the script is run as root
    if [ "$(id -u)" -ne 0 ]; then
        log_fatal "This script must be run as root. Please use sudo."
    fi

    # --- Check if user 'heads' exists ---
    if ! id "heads" &>/dev/null; then
        log_fatal "User 'heads' does not exist. Please create the user first."
    fi

    # --- Set password interactively ---
    log_info "Please set the password for the 'heads' user."
    local password
    local password_confirm
    read -s -p "Enter password: " password
    echo
    read -s -p "Confirm password: " password_confirm
    echo

    if [ "$password" != "$password_confirm" ]; then
        log_fatal "Passwords do not match. Aborting."
    fi

    if [ -z "$password" ]; then
        log_fatal "Password cannot be empty. Aborting."
    fi

    log_info "Setting password for 'heads' user..."
    echo "heads:$password" | chpasswd
    if [ $? -eq 0 ]; then
        log_info "Password for 'heads' user set successfully."
    else
        log_fatal "Failed to set password for 'heads' user."
    fi

    log_info "'heads' user password setting script completed successfully."
}

# --- Execute Main ---
main "$@"