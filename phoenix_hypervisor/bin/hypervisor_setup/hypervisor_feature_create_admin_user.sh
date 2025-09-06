#!/bin/bash

# File: hypervisor_feature_create_admin_user.sh
# Description: Creates and configures a system user and a corresponding Proxmox VE user
#              with Administrator role and sudo privileges. It also supports optional
#              SSH key configuration, with all settings read from `hypervisor_config.json`.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq, useradd, chpasswd,
#               groupadd, getent, grep, usermod, pveum, mkdir, chown, chmod, eval.
# Inputs:
#   Configuration values from HYPERVISOR_CONFIG_FILE: .users.username, .users.password_hash,
#   .users.sudo_access, .users.ssh_public_key.
# Outputs:
#   System user creation, Proxmox VE user creation, sudoers file modification,
#   SSH authorized_keys file modification, log messages to stdout and MAIN_LOG_FILE,
#   exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# Source common utilities
source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh # Source common utilities for logging and error handling

# Ensure script is run as root
check_root # Ensure the script is run with root privileges

log_info "Starting admin user creation and configuration."

# Read user configuration from hypervisor_config.json
log_info "Reading user configuration from $HYPERVISOR_CONFIG_FILE..."

# Retrieve user configuration details from the HYPERVISOR_CONFIG_FILE.
# This assumes a single admin user for now; in a more complex scenario,
# a 'role' field might be used to identify admin users.
USERNAME=$(jq -r '.users.username // ""' "$HYPERVISOR_CONFIG_FILE") # System username
PASSWORD_HASH=$(jq -r '.users.password_hash // ""' "$HYPERVISOR_CONFIG_FILE") # Hashed password for the user
SUDO_ACCESS=$(jq -r '.users.sudo_access // false' "$HYPERVISOR_CONFIG_FILE") # Boolean indicating sudo access
SSH_PUBLIC_KEY=$(jq -r '.users.ssh_public_key // ""' "$HYPERVISOR_CONFIG_FILE") # SSH public key for authentication

if [[ -z "$USERNAME" ]]; then
    log_fatal "No admin user defined in $HYPERVISOR_CONFIG_FILE. Cannot proceed."
fi

log_info "Configuring user: $USERNAME (Sudo Access: $SUDO_ACCESS)"

# create_system_user: Creates a system user with sudo privileges
# Args: None (uses global USERNAME, PASSWORD_HASH, SUDO_ACCESS)
# Returns: 0 on success or if user exists, 1 on failure
# =====================================================================================
# Function: create_system_user
# Description: Creates a new system user with a home directory and bash shell.
#              It sets a password if provided (hashed) and grants sudo privileges
#              if configured. This function is idempotent.
# Arguments:
#   None (uses global USERNAME, PASSWORD_HASH, SUDO_ACCESS).
# Returns:
#   None. Exits with a fatal error if user creation, password setting, or sudo
#   configuration fails.
# =====================================================================================
create_system_user() {
    log_info "Creating system user $USERNAME..."
    # Check if the user already exists
    if ! id "$USERNAME" >/dev/null 2>&1; then
        retry_command "useradd -m -s /bin/bash $USERNAME" || log_fatal "Failed to create system user $USERNAME" # Create user
        log_info "Created system user $USERNAME"
        # Set password if a hashed password is provided
        if [[ -n "$PASSWORD_HASH" && "$PASSWORD_HASH" != "NOT_SET" ]]; then
            # Using chpasswd with a hashed password is more secure for automated setups
            echo "$USERNAME:$PASSWORD_HASH" | chpasswd -e || log_fatal "Failed to set password for $USERNAME"
            log_info "Set password for system user $USERNAME"
        else
            log_warn "No password hash provided for user $USERNAME. User will not have a password set."
        fi
    else
        log_info "User $USERNAME already exists. Skipping user creation."
    fi

    # Grant sudo access if configured
    if [ "$SUDO_ACCESS" == "true" ]; then
        log_info "Granting sudo access to user $USERNAME."
        # Create 'sudo' group if it doesn't exist
        if ! getent group sudo >/dev/null; then
            retry_command "groupadd sudo" || log_fatal "Failed to create sudo group"
            log_info "Created sudo group"
        fi
        add_user_to_group "$USERNAME" "sudo" || log_fatal "Failed to add $USERNAME to sudo group" # Add user to sudo group
        # Configure sudoers file for the 'sudo' group
        if ! grep -q "%sudo ALL=(ALL:ALL) ALL" /etc/sudoers; then
            echo "%sudo ALL=(ALL:ALL) ALL" >> /etc/sudoers || log_fatal "Failed to configure sudoers for sudo group"
            log_info "Configured sudoers for sudo group"
        else
            log_info "Sudoers configuration for sudo group already exists, skipping"
        fi
    else
        log_info "Sudo access not requested for user $USERNAME. Skipping sudo configuration."
    fi
}

# create_proxmox_user: Creates a Proxmox VE user with Administrator role
# Args: None (uses global USERNAME)
# Returns: 0 on success or if user exists, 1 on failure
# =====================================================================================
# Function: create_proxmox_user
# Description: Creates a new Proxmox VE user with the 'Administrator' role.
#              This function is idempotent, checking if the user and role already exist.
# Arguments:
#   None (uses global USERNAME).
# Returns:
#   None. Exits with a fatal error if Proxmox user creation or role assignment fails.
# =====================================================================================
create_proxmox_user() {
    log_info "Creating Proxmox user $USERNAME@pam..."
    # Check if the Proxmox user already exists
    if pveum user list | grep -q "^$USERNAME@pam\$"; then
        log_info "Proxmox user $USERNAME@pam already exists, checking permissions"
        # Check if the user already has the Administrator role
        if ! pveum acl list | grep -q "^ / $USERNAME@pam .*Administrator\$"; then
            retry_command "pveum acl modify / -user $USERNAME@pam -role Administrator" || log_fatal "Failed to grant Proxmox admin role to user $USERNAME@pam"
            log_info "Granted Proxmox admin role to user $USERNAME@pam"
        else
            log_info "Proxmox user $USERNAME@pam already has Administrator role"
        fi
    else
        retry_command "pveum user add $USERNAME@pam" || log_fatal "Failed to create Proxmox user $USERNAME@pam" # Add Proxmox user
        retry_command "pveum acl modify / -user $USERNAME@pam -role Administrator" || log_fatal "Failed to grant Proxmox admin role to user $USERNAME@pam" # Grant Administrator role
        log_info "Created Proxmox user $USERNAME@pam with Administrator role"
    fi
}

# setup_ssh_key: Sets up SSH key for the user
# Args: None (uses global USERNAME, SSH_PUBLIC_KEY)
# Returns: 0 on success or if skipped, 1 on failure
# =====================================================================================
# Function: setup_ssh_key
# Description: Configures SSH public key authentication for the system user.
#              It creates the `.ssh` directory and `authorized_keys` file if they
#              don't exist, sets appropriate permissions, and appends the provided
#              SSH public key. This function is idempotent.
# Arguments:
#   None (uses global USERNAME, SSH_PUBLIC_KEY).
# Returns:
#   0 if no SSH public key is provided or if setup is successful, exits with a
#   fatal error if directory/file creation, ownership, or permissions fail.
# =====================================================================================
setup_ssh_key() {
    # If no SSH public key is provided, skip setup
    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        log_info "No SSH public key provided, skipping SSH key setup for $USERNAME"
        return 0
    fi

    log_info "Setting up SSH key for user $USERNAME."
    local user_home # Variable to store the user's home directory
    user_home=$(eval echo ~$USERNAME) || log_fatal "Could not determine home directory for $USERNAME" # Get user's home directory
    local ssh_dir="$user_home/.ssh" # Path to .ssh directory
    local auth_keys_file="$ssh_dir/authorized_keys" # Path to authorized_keys file

    # Create .ssh directory and set permissions/ownership
    retry_command "mkdir -p \"$ssh_dir\"" || log_fatal "Failed to create .ssh directory for $USERNAME"
    retry_command "chown \"$USERNAME:$USERNAME\" \"$ssh_dir\"" || log_fatal "Failed to set ownership for $ssh_dir"
    retry_command "chmod 700 \"$ssh_dir\"" || log_fatal "Failed to set permissions for $ssh_dir"
    
    # Append the SSH public key to authorized_keys if it's not already present
    if ! grep -qF "$SSH_PUBLIC_KEY" "$auth_keys_file" 2>/dev/null; then
        retry_command "echo \"$SSH_PUBLIC_KEY\" >> \"$auth_keys_file\"" || log_fatal "Failed to write SSH key to $auth_keys_file"
        log_info "Added SSH public key to $auth_keys_file"
    else
        log_info "SSH public key already exists in $auth_keys_file, skipping."
    fi

    # Set ownership and permissions for the authorized_keys file
    retry_command "chown \"$USERNAME:$USERNAME\" \"$auth_keys_file\"" || log_fatal "Failed to set ownership for $auth_keys_file"
    retry_command "chmod 600 \"$auth_keys_file\"" || log_fatal "Failed to set permissions for $auth_keys_file"
    log_info "SSH key successfully configured for user $USERNAME"
}

# Main execution
# =====================================================================================
# Function: main
# Description: Main execution flow for the admin user creation script.
# Arguments:
#   None.
# Returns:
#   Exits with status 0 on successful completion.
# =====================================================================================
main() {
    create_system_user # Create or update the system user
    create_proxmox_user # Create or update the Proxmox user
    setup_ssh_key # Set up SSH key for the user
    
    log_info "Successfully completed hypervisor_feature_create_admin_user.sh for user: $USERNAME"
    exit 0
}

main "$@"

log_info "Successfully completed hypervisor_feature_create_admin_user.sh for user: $USERNAME"
exit 0