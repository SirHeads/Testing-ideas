#!/bin/bash

# File: hypervisor_feature_create_heads_user.sh
# Description: This script creates and configures a privileged user named 'heads'.
#              This user is granted full administrative access on both the underlying Linux system (via sudo)
#              and within the Proxmox VE environment (via the Administrator role). Unlike other user creation
#              scripts in the Phoenix Hypervisor ecosystem, this script is interactive and prompts for a password,
#              making it suitable for initial, manual setup of a primary administrative account.
#              It is designed to be idempotent, safely handling cases where the user or permissions already exist.
#
# Dependencies:
#   - /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - Standard system utilities: `useradd`, `usermod`, `grep`, `pveum`, `chpasswd`.
#
# Inputs:
#   - Interactive password entry from the user running the script.
#
# Outputs:
#   - Creates a system user named 'heads'.
#   - Adds the 'heads' user to the 'sudo' group.
#   - Ensures the 'sudo' group has appropriate permissions in `/etc/sudoers`.
#   - Creates a Proxmox VE user named 'heads@pam'.
#   - Assigns the 'Administrator' role to the 'heads@pam' user.
#   - Sets the system password for the 'heads' user based on interactive input.
#   - Logs its progress to standard output.
#   - Exits with status 0 on success, or a non-zero status on failure.

# --- Source common utilities ---
# The script is in bin/hypervisor_setup, so we go up one level to bin
UTILS_PATH=$(dirname "$0")/../phoenix_hypervisor_common_utils.sh
if [ ! -f "$UTILS_PATH" ]; then
    echo "Fatal: Common utilities script not found at $UTILS_PATH"
    exit 1
fi
# shellcheck source=../phoenix_hypervisor_common_utils.sh
source "$UTILS_PATH"

# =====================================================================================
# Function: set_heads_password
# Description: Interactively prompts the user to set a password for the 'heads' user.
#              It includes confirmation to prevent typos and ensures the password is not empty.
#              This function is called by main() to handle the password setting process.
# Arguments:
#   None.
# Returns:
#   None. The script will exit with a fatal error if `chpasswd` fails.
# =====================================================================================
set_heads_password() {
    log_info "Please set the password for the 'heads' user."
    local password
    local password_confirm

    # Loop until a valid, matching password is provided.
    while true; do
        read -s -p "Enter password for 'heads': " password
        echo
        read -s -p "Confirm password: " password_confirm
        echo

        if [ "$password" != "$password_confirm" ]; then
            log_error "Passwords do not match. Please try again."
        elif [ -z "$password" ]; then
            log_error "Password cannot be empty. Please try again."
        else
            break # Exit loop if passwords match and are not empty.
        fi
    done

    log_info "Setting password for 'heads' user..."
    # Pipe the username and password to `chpasswd` to set the system password.
    echo "heads:$password" | chpasswd
    if [ $? -eq 0 ]; then
        log_info "Password for 'heads' user set successfully."
    else
        log_fatal "Failed to set password for 'heads' user."
    fi
}

# =====================================================================================
# Function: main
# Description: The main entry point for the script. It orchestrates the creation and
#              configuration of the 'heads' user, ensuring all necessary steps are
#              performed in the correct order.
# Arguments:
#   None.
# Returns:
#   None. Exits with status 0 on success.
# =====================================================================================
main() {
    log_info "Starting 'heads' user creation and configuration script."

    # Ensure the script is run as root, as it performs privileged operations.
    check_root

    # --- Create 'heads' system user ---
    log_info "Checking for 'heads' system user..."
    # Idempotency check: only create the user if they do not already exist.
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
    # Add the user to the 'sudo' group to grant administrative permissions.
    usermod -aG sudo heads
    if [ $? -eq 0 ]; then
        log_info "User 'heads' added to the sudo group."
    else
        # This may not be a fatal error if the user is already in the group.
        log_warn "Failed to add 'heads' user to the sudo group. This might not be an issue if the user was already in the group."
    fi

    log_info "Ensuring sudo group has appropriate permissions in /etc/sudoers..."
    # Idempotency check: ensure the sudoers file correctly configures the 'sudo' group.
    if ! grep -qxF '%sudo ALL=(ALL:ALL) ALL' /etc/sudoers; then
        log_info "'%sudo ALL=(ALL:ALL) ALL' not found in /etc/sudoers. Adding it."
        # Appending directly is generally safe for this specific, well-known line.
        echo '%sudo ALL=(ALL:ALL) ALL' >> /etc/sudoers
    else
        log_info "Sudo group permissions are correctly configured in /etc/sudoers."
    fi

    # --- Create and Configure Proxmox User ---
    log_info "Checking for Proxmox user 'heads@pam'..."
    # Idempotency check: Verify if the Proxmox user already exists before attempting creation.
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
    # This command is idempotent; running it multiple times has no adverse effect.
    pveum acl modify / -user heads@pam -role Administrator
    if [ $? -eq 0 ]; then
        log_info "Successfully assigned Administrator role to 'heads@pam'."
    else
        log_fatal "Failed to assign Administrator role to 'heads@pam'."
    fi

    # --- Set Password Interactively ---
    # Call the function to handle the interactive password prompt.
    set_heads_password

    log_info "'heads' user creation and configuration script completed successfully."
}

# --- Execute Main ---
main "$@"