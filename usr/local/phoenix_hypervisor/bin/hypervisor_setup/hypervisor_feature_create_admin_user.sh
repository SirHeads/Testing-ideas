#!/bin/bash

# File: hypervisor_feature_create_admin_user.sh
# Description: This script handles the declarative creation and configuration of an administrative user on the Proxmox hypervisor.
#              It ensures that a specified system user exists and is configured with the correct permissions, both at the OS level
#              (including sudo access) and within the Proxmox VE environment (with an Administrator role). The script is a key part
#              of the `--setup-hypervisor` orchestration process, establishing the necessary user accounts for managing the system.
#              All configurations are read from a central JSON configuration file, adhering to the declarative configuration principle.
#              The script is designed to be idempotent, ensuring it can be run multiple times without causing errors or unintended changes.
#
# Dependencies:
#   - /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - `jq`: For parsing the JSON configuration file.
#   - Standard system utilities: `useradd`, `chpasswd`, `groupadd`, `usermod`, `pveum`, `mkdir`, `chown`, `chmod`.
#
# Inputs:
#   - A path to a JSON configuration file (e.g., `phoenix_hypervisor_config.json`) passed as the first command-line argument.
#   - The JSON file is expected to contain a `.users` object with the following keys:
#     - `username`: The name of the administrative user.
#     - `password_hash`: The crypt-hashed password for the user.
#     - `sudo_access`: A boolean (`true` or `false`) to determine if the user should have sudo privileges.
#     - `ssh_public_key`: The public SSH key for the user for key-based authentication.
#
# Outputs:
#   - Creates a system user and group.
#   - Sets the user's password from the provided hash.
#   - Adds the user to the `sudo` group if specified.
#   - Creates a corresponding Proxmox VE user (`username@pam`).
#   - Assigns the `Administrator` role to the Proxmox VE user at the root level (`/`).
#   - Configures the user's `~/.ssh/authorized_keys` file with the provided public key.
#   - Logs its progress to standard output.
#   - Exits with status 0 on success, or a non-zero status on failure.

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# Ensure script is run as root, as user and system modifications are required.
check_root

log_info "Starting admin user creation and configuration."

# Get the configuration file path from the first argument. This is the entry point for declarative configuration.
if [ -z "$1" ]; then
    log_fatal "Configuration file path not provided."
fi
HYPERVISOR_CONFIG_FILE="$1"

# Read user configuration from the provided JSON file.
log_info "Reading user configuration from $HYPERVISOR_CONFIG_FILE..."

# Retrieve user configuration details using jq. Default values are provided to handle missing keys gracefully.
USERNAME=$(jq -r '.users.username // "phoenix_admin"' "$HYPERVISOR_CONFIG_FILE")
PASSWORD_HASH=$(jq -r '.users.password_hash // ""' "$HYPERVISOR_CONFIG_FILE")
SUDO_ACCESS=$(jq -r '.users.sudo_access // false' "$HYPERVISOR_CONFIG_FILE")
SSH_PUBLIC_KEY=$(jq -r '.users.ssh_public_key // ""' "$HYPERVISOR_CONFIG_FILE")

# Validate that a username was actually defined in the configuration.
if [[ -z "$USERNAME" ]]; then
    log_fatal "No admin user defined in $HYPERVISOR_CONFIG_FILE. Cannot proceed."
fi

log_info "Configuring user: $USERNAME (Sudo Access: $SUDO_ACCESS)"

# =====================================================================================
# Function: create_system_user
# Description: Creates a new system user with a home directory and bash shell. It idempotently
#              checks if the user exists before creation. It also sets the user's password
#              from a pre-computed hash and grants sudo privileges by adding the user to
#              the 'sudo' group if specified in the configuration.
# Arguments:
#   None. Uses the global variables: USERNAME, PASSWORD_HASH, SUDO_ACCESS.
# Returns:
#   None. The script will exit with a fatal error if any command fails.
# =====================================================================================
create_system_user() {
    log_info "Ensuring system user $USERNAME exists..."
    # Idempotency check: only create the user if they do not already exist.
    if ! id "$USERNAME" >/dev/null 2>&1; then
        retry_command "useradd -m -s /bin/bash $USERNAME" || log_fatal "Failed to create system user $USERNAME"
        log_info "Created system user $USERNAME"
        # Set password only if a valid hash is provided. This is crucial for declarative setup.
        if [[ -n "$PASSWORD_HASH" && "$PASSWORD_HASH" != "NOT_SET" ]]; then
            # Using chpasswd with the -e flag allows us to pass an encrypted (hashed) password directly.
            echo "$USERNAME:$PASSWORD_HASH" | chpasswd -e || log_fatal "Failed to set password for $USERNAME"
            log_info "Set password for system user $USERNAME"
        else
            log_warn "No password hash provided for user $USERNAME. User will not have a password set."
        fi
    else
        log_info "User $USERNAME already exists. Skipping user creation."
    fi

    # Grant sudo access based on the declarative configuration.
    if [ "$SUDO_ACCESS" == "true" ]; then
        log_info "Granting sudo access to user $USERNAME."
        # Ensure the 'sudo' group exists, creating it if necessary.
        if ! getent group sudo >/dev/null; then
            retry_command "groupadd sudo" || log_fatal "Failed to create sudo group"
            log_info "Created sudo group"
        fi
        # Add the user to the 'sudo' group to grant privileges.
        add_user_to_group "$USERNAME" "sudo" || log_fatal "Failed to add $USERNAME to sudo group"
        # Ensure the /etc/sudoers file is configured to grant privileges to the 'sudo' group.
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

# =====================================================================================
# Function: create_proxmox_user
# Description: Creates a corresponding Proxmox VE user (e.g., 'username@pam') and assigns
#              it the 'Administrator' role. This provides the user with full administrative
#              privileges within the Proxmox web UI and API. The function is idempotent,
#              checking if the user and role assignment already exist.
# Arguments:
#   None. Uses the global variable: USERNAME.
# Returns:
#   None. The script will exit with a fatal error if any `pveum` command fails.
# =====================================================================================
create_proxmox_user() {
    log_info "Ensuring Proxmox user $USERNAME@pam exists and has admin role..."
    # Idempotency check: Use the Proxmox User Manager (`pveum`) with JSON output to reliably check if the user exists.
    if pveum user list --output-format json | jq -e ".[] | select(.userid == \"$USERNAME@pam\")" > /dev/null; then
        log_info "Proxmox user $USERNAME@pam already exists."
    else
        log_info "Proxmox user $USERNAME@pam does not exist. Creating..."
        retry_command "pveum user add $USERNAME@pam" || log_fatal "Failed to create Proxmox user $USERNAME@pam"
        log_info "Created Proxmox user $USERNAME@pam."
    fi

    # Idempotency check for role assignment. This prevents errors on subsequent runs.
    log_info "Ensuring Proxmox user $USERNAME@pam has Administrator role."
    if ! (pveum acl list --output-format json | jq -e ".[] | select(.path == \"/\") | .roles | select(has(\"$USERNAME@pam\") and .[\"$USERNAME@pam\"] == \"Administrator\")" > /dev/null); then
        # Assign the Administrator role at the root path '/' for full system access.
        retry_command "pveum acl modify / -user $USERNAME@pam -role Administrator" || log_fatal "Failed to grant Proxmox admin role to user $USERNAME@pam"
        log_info "Granted Proxmox admin role to user $USERNAME@pam"
    else
        log_info "Proxmox user $USERNAME@pam already has Administrator role."
    fi
}

# =====================================================================================
# Function: setup_ssh_key
# Description: Configures SSH public key authentication for the system user. It creates the
#              `~/.ssh` directory and `authorized_keys` file if they don't exist, sets the
#              strict permissions required by SSH, and appends the public key from the
#              configuration. This is the standard and secure way to enable remote access.
# Arguments:
#   None. Uses the global variables: USERNAME, SSH_PUBLIC_KEY.
# Returns:
#   0 if no SSH public key is provided. Otherwise, the script will exit with a fatal
#   error if any file or permission operations fail.
# =====================================================================================
setup_ssh_key() {
    # If no SSH public key is provided in the config, skip this entire process.
    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        log_info "No SSH public key provided, skipping SSH key setup for $USERNAME"
        return 0
    fi

    log_info "Setting up SSH key for user $USERNAME."
    # Reliably determine the user's home directory.
    local user_home
    user_home=$(eval echo ~$USERNAME) || log_fatal "Could not determine home directory for $USERNAME"
    local ssh_dir="$user_home/.ssh"
    local auth_keys_file="$ssh_dir/authorized_keys"

    # Create .ssh directory and set permissions/ownership. Permissions must be 700.
    retry_command "mkdir -p \"$ssh_dir\"" || log_fatal "Failed to create .ssh directory for $USERNAME"
    retry_command "chown \"$USERNAME:$USERNAME\" \"$ssh_dir\"" || log_fatal "Failed to set ownership for $ssh_dir"
    retry_command "chmod 700 \"$ssh_dir\"" || log_fatal "Failed to set permissions for $ssh_dir"
    
    # Idempotency check: Append the SSH public key to authorized_keys only if it's not already present.
    if ! grep -qF "$SSH_PUBLIC_KEY" "$auth_keys_file" 2>/dev/null; then
        retry_command "echo \"$SSH_PUBLIC_KEY\" >> \"$auth_keys_file\"" || log_fatal "Failed to write SSH key to $auth_keys_file"
        log_info "Added SSH public key to $auth_keys_file"
    else
        log_info "SSH public key already exists in $auth_keys_file, skipping."
    fi

    # Set ownership and permissions for the authorized_keys file. Permissions must be 600.
    retry_command "chown \"$USERNAME:$USERNAME\" \"$auth_keys_file\"" || log_fatal "Failed to set ownership for $auth_keys_file"
    retry_command "chmod 600 \"$auth_keys_file\"" || log_fatal "Failed to set permissions for $auth_keys_file"
    log_info "SSH key successfully configured for user $USERNAME"
}

# =====================================================================================
# Function: main
# Description: Main execution flow for the admin user creation script. It orchestrates
#              the calls to the other functions in the correct sequence to ensure a fully
#              configured administrative user.
# Arguments:
#   None.
# Returns:
#   Exits with status 0 on successful completion.
# =====================================================================================
main() {
    create_system_user
    create_proxmox_user
    setup_ssh_key
    
    log_info "Successfully completed hypervisor_feature_create_admin_user.sh for user: $USERNAME"
    exit 0
}

# --- Main execution ---
# The script's entry point.
main "$@"