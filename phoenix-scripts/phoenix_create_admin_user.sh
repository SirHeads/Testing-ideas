# Metadata: {"chunk_id": "phoenix_create_admin_user-1.0", "keywords": ["user", "proxmox", "ssh", "admin"], "comment_type": "block"}
#!/bin/bash
# phoenix_create_admin_user.sh
# Creates a system and Proxmox VE admin user with sudo privileges and optional SSH key configuration for the Phoenix server
# Version: 1.2.1 (Revised for common.sh integration)
# Author: Heads, Grok, Devstral

# Main: Creates and configures a system and Proxmox VE admin user
# Args: -u username, -p password (optional), -s ssh_public_key (optional)
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_create_admin_user-1.1", "keywords": ["user", "proxmox", "admin"], "comment_type": "block"}
# Algorithm: User creation and configuration
# Parses options, prompts for inputs, creates system and Proxmox users, sets up SSH key
# Keywords: [user, proxmox, ssh, admin]
# TODO: Support configurable group for user creation

# Source common functions for shared utilities
# Metadata: {"chunk_id": "phoenix_create_admin_user-1.2", "keywords": ["common", "utils"], "comment_type": "block"}
source /usr/local/bin/common.sh || { echo "[$(date)] Error: Failed to source common.sh" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }

# Parse command-line options
# Metadata: {"chunk_id": "phoenix_create_admin_user-1.3", "keywords": ["args", "parse"], "comment_type": "block"}
USERNAME=""
PASSWORD=""
SSH_PUBLIC_KEY=""
while getopts "u:p:s:" opt; do
  case $opt in
    u) USERNAME="$OPTARG" ;;
    p) PASSWORD="$OPTARG" ;;
    s) SSH_PUBLIC_KEY="$OPTARG" ;;
    \?) echo "[$(date)] Invalid option: -$OPTARG" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1 ;;
    :) echo "[$(date)] Option -$OPTARG requires an argument." | tee -a "${LOGFILE:-/dev/stderr}"; exit 1 ;;
  esac
done

# prompt_for_username: Prompts for username if not provided
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_create_admin_user-1.4", "keywords": ["user", "prompt"], "comment_type": "block"}
# Algorithm: Username prompting
# Prompts for username, validates format
# Keywords: [user, prompt]
prompt_for_username() {
    DEFAULT_USERNAME="heads"
    if [[ -z "$USERNAME" ]]; then
        read -p "Enter new admin username [$DEFAULT_USERNAME]: " USERNAME
        USERNAME=${USERNAME:-$DEFAULT_USERNAME}
    fi
    if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        echo "[$(date)] Error: Username must start with a letter or number and can only contain letters, numbers, hyphens, or underscores." | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
    fi
    echo "[$(date)] Set USERNAME to $USERNAME" >> "${LOGFILE:-/dev/stderr}"
}

# prompt_for_password: Prompts for password if not provided
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_create_admin_user-1.5", "keywords": ["password", "prompt"], "comment_type": "block"}
# Algorithm: Password prompting
# Prompts for password, validates length and special characters
# Keywords: [password, prompt]
# TODO: Enhance password complexity validation
prompt_for_password() {
    DEFAULT_PASSWORD="Kick@$$2025"
    if [[ -z "$PASSWORD" ]]; then
        read -s -p "Enter password for user $USERNAME (min 8 chars, 1 special char) [$DEFAULT_PASSWORD]: " PASSWORD
        echo
        PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}
    fi
    if [[ ! "$PASSWORD" =~ [[:punct:]] || ${#PASSWORD} -lt 8 ]]; then
        echo "[$(date)] Error: Password must be at least 8 characters long and contain at least one special character." | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
    fi
    echo "[$(date)] Set PASSWORD for user $USERNAME" >> "${LOGFILE:-/dev/stderr}"
}

# create_system_user: Creates a system user with sudo privileges
# Args: None (uses global USERNAME, PASSWORD)
# Returns: 0 on success or if user exists, 1 on failure
# Metadata: {"chunk_id": "phoenix_create_admin_user-1.6", "keywords": ["user", "system", "sudo"], "comment_type": "block"}
# Algorithm: System user creation
# Creates user, sets password, adds to sudo group, configures sudoers
# Keywords: [user, system, sudo]
create_system_user() {
    if ! id "$USERNAME" >/dev/null 2>&1; then
        retry_command "useradd -m -s /bin/bash $USERNAME" || { echo "[$(date)] Error: Failed to create system user $USERNAME" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
        echo "[$(date)] Created system user $USERNAME" >> "${LOGFILE:-/dev/stderr}"
        retry_command "echo \"$USERNAME:$PASSWORD\" | chpasswd" || { echo "[$(date)] Error: Failed to set password for $USERNAME" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
        echo "[$(date)] Set password for system user $USERNAME" >> "${LOGFILE:-/dev/stderr}"
    else
        echo "[$(date)] User $USERNAME already exists. Skipping user creation." >> "${LOGFILE:-/dev/stderr}"
    fi
    if ! getent group sudo >/dev/null; then
        retry_command "groupadd sudo" || { echo "[$(date)] Error: Failed to create sudo group" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
        echo "[$(date)] Created sudo group" >> "${LOGFILE:-/dev/stderr}"
    fi
    retry_command "usermod -aG sudo $USERNAME" || { echo "[$(date)] Error: Failed to add $USERNAME to sudo group" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
    echo "[$(date)] Added user $USERNAME to group sudo" >> "${LOGFILE:-/dev/stderr}"
    if ! grep -q "%sudo ALL=(ALL:ALL) ALL" /etc/sudoers; then
        echo "%sudo ALL=(ALL:ALL) ALL" >> /etc/sudoers || { echo "[$(date)] Error: Failed to configure sudoers for sudo group" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
        echo "[$(date)] Configured sudoers for sudo group" >> "${LOGFILE:-/dev/stderr}"
    else
        echo "[$(date)] Sudoers configuration for sudo group already exists, skipping" >> "${LOGFILE:-/dev/stderr}"
    fi
}

# create_proxmox_user: Creates a Proxmox VE user with Administrator role
# Args: None (uses global USERNAME)
# Returns: 0 on success or if user exists, 1 on failure
# Metadata: {"chunk_id": "phoenix_create_admin_user-1.7", "keywords": ["proxmox", "user"], "comment_type": "block"}
# Algorithm: Proxmox user creation
# Creates Proxmox user, grants Administrator role
# Keywords: [proxmox, user]
create_proxmox_user() {
    if pveum user list | grep -q "^$USERNAME@pam\$"; then
        echo "[$(date)] Proxmox user $USERNAME@pam already exists, checking permissions" >> "${LOGFILE:-/dev/stderr}"
        if ! pveum acl list | grep -q "^ / $USERNAME@pam .*Administrator\$"; then
            retry_command "pveum acl modify / -user $USERNAME@pam -role Administrator" || { echo "[$(date)] Error: Failed to grant Proxmox admin role to user $USERNAME@pam" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
            echo "[$(date)] Granted Proxmox admin role to user $USERNAME@pam" >> "${LOGFILE:-/dev/stderr}"
        else
            echo "[$(date)] Proxmox user $USERNAME@pam already has Administrator role" >> "${LOGFILE:-/dev/stderr}"
        fi
    else
        retry_command "pveum user add $USERNAME@pam" || { echo "[$(date)] Error: Failed to create Proxmox user $USERNAME@pam" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
        retry_command "pveum acl modify / -user $USERNAME@pam -role Administrator" || { echo "[$(date)] Error: Failed to grant Proxmox admin role to user $USERNAME@pam" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
        echo "[$(date)] Created Proxmox user $USERNAME@pam with Administrator role" >> "${LOGFILE:-/dev/stderr}"
    fi
}

# setup_ssh_key: Sets up SSH key for the user
# Args: None (uses global USERNAME, SSH_PUBLIC_KEY)
# Returns: 0 on success or if skipped, 1 on failure
# Metadata: {"chunk_id": "phoenix_create_admin_user-1.8", "keywords": ["ssh", "user", "key"], "comment_type": "block"}
# Algorithm: SSH key setup
# Creates .ssh directory, sets permissions, adds public key
# Keywords: [ssh, user, key]
# TODO: Validate SSH key file existence if provided as a path
setup_ssh_key() {
    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        echo "[$(date)] No SSH public key provided, skipping SSH key setup for $USERNAME" >> "${LOGFILE:-/dev/stderr}"
        return 0
    fi
    if ! [[ "$SSH_PUBLIC_KEY" =~ ^(ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|ed25519) ]]; then
        echo "[$(date)] Error: Invalid SSH public key format. Key must start with 'ssh-rsa', 'ecdsa-sha2-nistp256', 'ecdsa-sha2-nistp384', 'ecdsa-sha2-nistp521', or 'ed25519'." | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
    fi
    local user_home
    user_home=$(eval echo ~$USERNAME) || {
        echo "[$(date)] Error: Could not determine home directory for $USERNAME" | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
    }
    local ssh_dir="$user_home/.ssh"
    local auth_keys_file="$ssh_dir/authorized_keys"
    retry_command "mkdir -p \"$ssh_dir\"" || {
        echo "[$(date)] Error: Failed to create .ssh directory for $USERNAME" | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
    }
    retry_command "chown \"$USERNAME:$USERNAME\" \"$ssh_dir\"" || {
        echo "[$(date)] Error: Failed to set ownership for $ssh_dir" | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
    }
    retry_command "chmod 700 \"$ssh_dir\"" || {
        echo "[$(date)] Error: Failed to set permissions for $ssh_dir" | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
    }
    retry_command "echo \"$SSH_PUBLIC_KEY\" >> \"$auth_keys_file\"" || {
        echo "[$(date)] Error: Failed to write SSH key to $auth_keys_file" | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
    }
    retry_command "chown \"$USERNAME:$USERNAME\" \"$auth_keys_file\"" || {
        echo "[$(date)] Error: Failed to set ownership for $auth_keys_file" | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
    }
    retry_command "chmod 600 \"$auth_keys_file\"" || {
        echo "[$(date)] Error: Failed to set permissions for $auth_keys_file" | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
    }
    echo "[$(date)] SSH key successfully added for user $USERNAME" >> "${LOGFILE:-/dev/stderr}"
}

# Main execution
# Metadata: {"chunk_id": "phoenix_create_admin_user-1.9", "keywords": ["execution"], "comment_type": "block"}
check_root
prompt_for_username
prompt_for_password
create_system_user
create_proxmox_user
setup_ssh_key
echo "[$(date)] Successfully completed phoenix_create_admin_user.sh for user: $USERNAME" >> "${LOGFILE:-/dev/stderr}"
exit 0