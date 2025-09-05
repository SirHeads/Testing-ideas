#!/bin/bash

# File: hypervisor_feature_create_admin_user.sh
# Description: Creates a system and Proxmox VE admin user with sudo privileges and
#              optional SSH key configuration, reading settings from hypervisor_config.json.
# Version: 1.0.0
# Author: Roo (AI Architect)

# Source common utilities
source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh

# Ensure script is run as root
check_root

log_info "Starting admin user creation and configuration."

# Read user configuration from hypervisor_config.json
log_info "Reading user configuration from $HYPERVISOR_CONFIG_FILE..."

# Assuming a single admin user for now, or iterating if multiple users are defined as admin
# For simplicity, let's assume the first user in the 'users' array is the admin.
# In a more complex scenario, we might add a 'role' field to the user object in the config.
USERNAME=$(jq -r '.users.username // ""' "$HYPERVISOR_CONFIG_FILE")
PASSWORD_HASH=$(jq -r '.users.password_hash // ""' "$HYPERVISOR_CONFIG_FILE")
SUDO_ACCESS=$(jq -r '.users.sudo_access // false' "$HYPERVISOR_CONFIG_FILE")
SSH_PUBLIC_KEY=$(jq -r '.users.ssh_public_key // ""' "$HYPERVISOR_CONFIG_FILE")

if [[ -z "$USERNAME" ]]; then
    log_fatal "No admin user defined in $HYPERVISOR_CONFIG_FILE. Cannot proceed."
fi

log_info "Configuring user: $USERNAME (Sudo Access: $SUDO_ACCESS)"

# create_system_user: Creates a system user with sudo privileges
# Args: None (uses global USERNAME, PASSWORD_HASH, SUDO_ACCESS)
# Returns: 0 on success or if user exists, 1 on failure
create_system_user() {
    log_info "Creating system user $USERNAME..."
    if ! id "$USERNAME" >/dev/null 2>&1; then
        retry_command "useradd -m -s /bin/bash $USERNAME" || log_fatal "Failed to create system user $USERNAME"
        log_info "Created system user $USERNAME"
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

    if [ "$SUDO_ACCESS" == "true" ]; then
        log_info "Granting sudo access to user $USERNAME."
        if ! getent group sudo >/dev/null; then
            retry_command "groupadd sudo" || log_fatal "Failed to create sudo group"
            log_info "Created sudo group"
        fi
        add_user_to_group "$USERNAME" "sudo" || log_fatal "Failed to add $USERNAME to sudo group"
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
create_proxmox_user() {
    log_info "Creating Proxmox user $USERNAME@pam..."
    if pveum user list | grep -q "^$USERNAME@pam\$"; then
        log_info "Proxmox user $USERNAME@pam already exists, checking permissions"
        if ! pveum acl list | grep -q "^ / $USERNAME@pam .*Administrator\$"; then
            retry_command "pveum acl modify / -user $USERNAME@pam -role Administrator" || log_fatal "Failed to grant Proxmox admin role to user $USERNAME@pam"
            log_info "Granted Proxmox admin role to user $USERNAME@pam"
        else
            log_info "Proxmox user $USERNAME@pam already has Administrator role"
        fi
    else
        retry_command "pveum user add $USERNAME@pam" || log_fatal "Failed to create Proxmox user $USERNAME@pam"
        retry_command "pveum acl modify / -user $USERNAME@pam -role Administrator" || log_fatal "Failed to grant Proxmox admin role to user $USERNAME@pam"
        log_info "Created Proxmox user $USERNAME@pam with Administrator role"
    fi
}

# setup_ssh_key: Sets up SSH key for the user
# Args: None (uses global USERNAME, SSH_PUBLIC_KEY)
# Returns: 0 on success or if skipped, 1 on failure
setup_ssh_key() {
    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        log_info "No SSH public key provided, skipping SSH key setup for $USERNAME"
        return 0
    fi

    log_info "Setting up SSH key for user $USERNAME."
    local user_home
    user_home=$(eval echo ~$USERNAME) || log_fatal "Could not determine home directory for $USERNAME"
    local ssh_dir="$user_home/.ssh"
    local auth_keys_file="$ssh_dir/authorized_keys"

    retry_command "mkdir -p \"$ssh_dir\"" || log_fatal "Failed to create .ssh directory for $USERNAME"
    retry_command "chown \"$USERNAME:$USERNAME\" \"$ssh_dir\"" || log_fatal "Failed to set ownership for $ssh_dir"
    retry_command "chmod 700 \"$ssh_dir\"" || log_fatal "Failed to set permissions for $ssh_dir"
    
    # Append the key if it's not already there
    if ! grep -qF "$SSH_PUBLIC_KEY" "$auth_keys_file" 2>/dev/null; then
        retry_command "echo \"$SSH_PUBLIC_KEY\" >> \"$auth_keys_file\"" || log_fatal "Failed to write SSH key to $auth_keys_file"
        log_info "Added SSH public key to $auth_keys_file"
    else
        log_info "SSH public key already exists in $auth_keys_file, skipping."
    fi

    retry_command "chown \"$USERNAME:$USERNAME\" \"$auth_keys_file\"" || log_fatal "Failed to set ownership for $auth_keys_file"
    retry_command "chmod 600 \"$auth_keys_file\"" || log_fatal "Failed to set permissions for $auth_keys_file"
    log_info "SSH key successfully configured for user $USERNAME"
}

# Main execution
create_system_user
create_proxmox_user
setup_ssh_key

log_info "Successfully completed hypervisor_feature_create_admin_user.sh for user: $USERNAME"
exit 0