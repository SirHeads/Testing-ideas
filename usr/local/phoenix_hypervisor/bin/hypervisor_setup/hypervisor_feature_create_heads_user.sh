#!/bin/bash

# -----------------------------------------------------------------------------
# Script: hypervisor_feature_create_heads_user.sh
# Description: Creates and configures the 'heads' user with full administrative
#              privileges on both the Linux system and Proxmox.
#
# Usage:
#   sudo ./hypervisor_feature_create_heads_user.sh
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
    log_info "Starting 'heads' user creation and configuration script."

    # Ensure the script is run as root
    if [ "$(id -u)" -ne 0 ]; then
        log_fatal "This script must be run as root. Please use sudo."
    fi

    # --- Create 'heads' system user ---
    log_info "Checking for 'heads' system user..."
    if id "heads" &>/dev/null; then
        log_info "User 'heads' already exists. Skipping creation."
    else
        log_info "User 'heads' not found. Creating user..."
        useradd -m -s /bin/bash heads
        if [ $? -eq 0 ]; then
            log_info "Successfully created system user 'heads'."
        else
            log_fatal "Failed to create system user 'heads'."
        fi
    fi

    # --- Grant Sudo Privileges ---
    log_info "Granting sudo privileges to 'heads' user..."
    usermod -aG sudo heads
    if [ $? -eq 0 ]; then
        log_info "User 'heads' added to the sudo group."
    else
        log_warn "Failed to add 'heads' user to the sudo group. This might not be an issue if the user was already in the group."
    fi

    log_info "Ensuring sudo group has appropriate permissions in /etc/sudoers..."
    if ! grep -qxF '%sudo ALL=(ALL:ALL) ALL' /etc/sudoers; then
        log_info "'%sudo ALL=(ALL:ALL) ALL' not found in /etc/sudoers. Adding it."
        # Use a temp file and visudo for safer editing
        echo '%sudo ALL=(ALL:ALL) ALL' >> /etc/sudoers
    else
        log_info "Sudo group permissions are correctly configured in /etc/sudoers."
    fi

    # --- Create and Configure Proxmox User ---
    log_info "Checking for Proxmox user 'heads@pam'..."
    if pveum user list | grep -q 'heads@pam'; then
        log_info "Proxmox user 'heads@pam' already exists."
    else
        log_info "Creating Proxmox user 'heads@pam'..."
        pveum user add heads@pam
        if [ $? -eq 0 ]; then
            log_info "Successfully created Proxmox user 'heads@pam'."
        else
            log_fatal "Failed to create Proxmox user 'heads@pam'."
        fi
    fi

    log_info "Assigning Administrator role to Proxmox user 'heads@pam'..."
    pveum acl modify / -user heads@pam -role Administrator
    if [ $? -eq 0 ]; then
        log_info "Successfully assigned Administrator role to 'heads@pam'."
    else
        log_fatal "Failed to assign Administrator role to 'heads@pam'."
    fi

    log_info "'heads' user creation and configuration script completed successfully."
}

# --- Execute Main ---
main "$@"