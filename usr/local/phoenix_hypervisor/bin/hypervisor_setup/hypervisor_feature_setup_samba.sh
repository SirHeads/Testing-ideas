#!/bin/bash

# File: hypervisor_feature_setup_samba.sh
# Description: Configures a Samba file server on a Proxmox VE host.
#              This script sets up Samba shares for specified paths (typically ZFS datasets),
#              configures user authentication, and applies firewall rules.
#              All share and user settings are read from `hypervisor_config.json`.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq, id, pdbedit,
#               apt-get, samba, samba-common-bin, smbclient, systemctl, ufw, grep, cp.
# Inputs:
#   Configuration values from HYPERVISOR_CONFIG_FILE: .users.username, .network.workgroup,
#   .samba_shares[] (name, path, browsable, read_only, guest_ok, valid_users[]).
# Outputs:
#   Samba package installation logs, `/etc/samba/smb.conf` modifications, UFW firewall
#   rule additions, Samba user configuration, log messages to stdout and MAIN_LOG_FILE,
#   exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# Ensure script is run as root
check_root # Ensure the script is run with root privileges

log_info "Starting Samba server and shares setup."

# Read Samba configuration from hypervisor_config.json
log_info "Reading Samba configuration from $HYPERVISOR_CONFIG_FILE..."

# Assuming a single admin user for Samba for now, or iterating if multiple users are defined with samba access
SMB_USER=$(jq -r '.users.username // "heads"' "$HYPERVISOR_CONFIG_FILE")
# Note: The original script prompted for password or used a default.
# For 1:1 porting, we'll assume the password hash is not directly used for Samba,
# but the user is expected to be created with a password via hypervisor_feature_create_admin_user.sh
# and then added to Samba via smbpasswd.
# For now, we'll use a placeholder and rely on manual `smbpasswd` if not set.
SMB_PASSWORD_PLACEHOLDER="NOT_SET_VIA_CONFIG" # Samba passwords are set interactively or via pipe
NETWORK_NAME=$(jq -r '.network.workgroup // "WORKGROUP"' "$HYPERVISOR_CONFIG_FILE")
MOUNT_POINT_BASE="/mnt/pve" # This is a constant in the new structure

# Validate that the configured Samba system user exists
if ! id "$SMB_USER" >/dev/null 2>&1; then
  log_fatal "System user $SMB_USER does not exist. Please create it first."
fi
log_info "Verified that Samba system user $SMB_USER exists"

# Validate the network name (workgroup) format
if [[ ! "$NETWORK_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  log_fatal "Network name '$NETWORK_NAME' must contain only letters, numbers, hyphens, or underscores."
fi
log_info "Set Samba workgroup to $NETWORK_NAME"

# install_samba: Installs Samba packages if not present
# Args: None
# Returns: 0 on success, 1 on failure
# =====================================================================================
# Function: install_samba
# Description: Installs the Samba server and client packages if they are not already present.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if package installation fails.
# =====================================================================================
install_samba() {
  # Check if Samba is already installed
  if ! check_package samba; then
    retry_command "apt-get update" || log_fatal "Failed to update package lists" # Update package lists
    retry_command "apt-get install -y samba samba-common-bin smbclient" || log_fatal "Failed to install Samba" # Install Samba packages
    log_info "Installed Samba"
  else
    log_info "Samba already installed, skipping installation"
  fi
}

# configure_samba_user: Sets Samba password for the configured user
# Args: None (uses global SMB_USER)
# Returns: 0 on success, 1 on failure
# =====================================================================================
# Function: configure_samba_user
# Description: Configures the specified system user for Samba access.
#              It checks if the Samba user exists and provides instructions for
#              manual password setup if needed, as automated password piping
#              is not directly implemented for security/complexity reasons in this port.
# Arguments:
#   None (uses global SMB_USER).
# Returns:
#   None.
# =====================================================================================
configure_samba_user() {
  log_info "Configuring Samba user: $SMB_USER"
  # Check if the Samba user exists in the Samba password database
  if ! pdbedit -L | grep -q "^$SMB_USER:"; then
    log_warn "Samba user $SMB_USER does not exist. Please set the Samba password manually using 'smbpasswd -a $SMB_USER'."
    # Note: In a fully automated scenario, a password could be piped to smbpasswd.
    # This port reflects the original script's approach of manual or pre-set password.
  else
    log_info "Samba user $SMB_USER already exists. Skipping password setup (assuming it's already set or will be set manually)."
  fi
}

# configure_samba_shares: Creates mount points for Samba shares and sets permissions
# Args: None
# Returns: 0 on success, 1 on failure
# =====================================================================================
# Function: configure_samba_shares
# Description: Creates and configures mount points and permissions for Samba shares
#              based on definitions in `hypervisor_config.json`.
# Arguments:
#   None (uses global MOUNT_POINT_BASE, SMB_USER, HYPERVISOR_CONFIG_FILE).
# Returns:
#   None. Exits with a fatal error if directory creation, ownership, or permissions fail.
# =====================================================================================
configure_samba_shares() {
  log_info "Configuring Samba share mount points and permissions..."
  mkdir -p "$MOUNT_POINT_BASE" || log_fatal "Failed to create $MOUNT_POINT_BASE" # Ensure base mount point exists

  local samba_shares_config # Variable to store Samba shares configuration
  samba_shares_config=$(jq -c '.samba.shares[]' "$HYPERVISOR_CONFIG_FILE") # Retrieve Samba shares array from config

  # Iterate through each Samba share defined in the configuration
  for share_json in $samba_shares_config; do
    local share_name=$(echo "$share_json" | jq -r '.name') # Name of the Samba share
    local path=$(echo "$share_json" | jq -r '.path') # Path to the shared directory
    local valid_users_array=($(echo "$share_json" | jq -r '.valid_users[]')) # Array of valid users
    local valid_users_str=$(IFS=,; echo "${valid_users_array[*]}") # Convert valid users array to comma-separated string

    # Skip if the share path is missing
    if [[ -z "$path" ]]; then
      log_warn "Skipping Samba share '$share_name' due to missing path in configuration."
      continue
    fi

    # Ensure the directory exists
    # Ensure the directory for the Samba share exists
    mkdir -p "$path" || log_fatal "Failed to create directory for Samba share: $path"

    # Set ownership and permissions
    # Set ownership and permissions for the shared directory
    retry_command "chown $SMB_USER:$SMB_USER \"$path\"" || log_fatal "Failed to set ownership for $path"
    retry_command "chmod 770 \"$path\"" || log_fatal "Failed to set permissions for $path"
    log_info "Created and configured mountpoint $path for Samba share '$share_name'"
  done
}

# configure_samba_config: Configures Samba shares in smb.conf
# Args: None
# Returns: 0 on success, 1 on failure
# =====================================================================================
# Function: configure_samba_config
# Description: Configures Samba global settings and defines individual shares
#              in `/etc/samba/smb.conf` based on `hypervisor_config.json`.
#              It backs up the existing `smb.conf` and then generates a new one.
# Arguments:
#   None (uses global NETWORK_NAME, HYPERVISOR_CONFIG_FILE).
# Returns:
#   None. Exits with a fatal error if backing up or writing `smb.conf` fails.
# =====================================================================================
configure_samba_config() {
  log_info "Configuring Samba global settings and shares in /etc/samba/smb.conf..."
  local smb_conf_file="/etc/samba/smb.conf" # Path to the Samba configuration file

  # Backup the existing smb.conf file if it exists
  if [[ -f "$smb_conf_file" ]]; then
    cp "$smb_conf_file" "$smb_conf_file.bak.$(date +%F_%H-%M-%S)" || log_fatal "Failed to back up $smb_conf_file"
    log_info "Backed up $smb_conf_file"
  fi

  # Start with global settings
  # Write global Samba settings to smb.conf
  # Write a modern, streamlined global Samba settings to smb.conf
  cat << EOF > "$smb_conf_file"
[global]
   workgroup = $NETWORK_NAME
   server string = %h Proxmox Samba Server
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   panic action = /usr/share/samba/panic-action %d
   server role = standalone server
   obey pam restrictions = yes
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
   pam password change = yes
   map to guest = bad user
   usershare allow guests = yes
EOF

  local samba_shares_config # Variable to store Samba shares configuration
  samba_shares_config=$(jq -c '.samba.shares[]' "$HYPERVISOR_CONFIG_FILE") # Retrieve Samba shares array from config

  # Iterate through each Samba share and append its configuration to smb.conf
  for share_json in $samba_shares_config; do
    local share_name=$(echo "$share_json" | jq -r '.name') # Name of the share
    local path=$(echo "$share_json" | jq -r '.path') # Path to the shared directory
    local browsable=$(echo "$share_json" | jq -r '.browsable // true') # Browsable setting
    local read_only=$(echo "$share_json" | jq -r '.read_only // false') # Read-only setting
    local guest_ok=$(echo "$share_json" | jq -r '.guest_ok // false') # Guest access setting
    local valid_users_array=($(echo "$share_json" | jq -r '.valid_users[]')) # Array of valid users
    local valid_users_str=$(IFS=,; echo "${valid_users_array[*]}") # Comma-separated string of valid users

    # Convert boolean to yes/no
    # Convert boolean settings to "yes" or "no" strings for smb.conf
    browsable_str="no"
    if [ "$browsable" == "true" ]; then browsable_str="yes"; fi
    writable_str="no"
    if [ "$read_only" == "false" ]; then writable_str="yes"; fi
    guest_ok_str="no"
    if [ "$guest_ok" == "true" ]; then guest_ok_str="yes"; fi

    cat << EOF >> "$smb_conf_file"

[$share_name]
   path = $path
   writable = $writable_str
   browsable = $browsable_str
   guest ok = $guest_ok_str
   valid users = $valid_users_str
   create mask = 0770
   directory mask = 0770
   force create mode = 0770
   force directory mode = 0770
EOF
    log_info "Added Samba share '$share_name' for path $path to $smb_conf_file"
  done
  log_info "Samba shares configured."
}

# configure_samba_firewall: Configures firewall for Samba
# Args: None
# Returns: 0 on success, 1 on failure
# =====================================================================================
# Function: configure_samba_firewall
# Description: Configures the Uncomplicated Firewall (UFW) to allow necessary Samba
#              traffic (ports 137/udp, 138/udp, 139/tcp, 445/tcp). It checks for
#              existing rules and adds them if needed.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if firewall rules cannot be applied.
# =====================================================================================
configure_samba_firewall() {
  log_info "Configuring firewall for Samba..."
  local ports=("137/udp" "138/udp" "139/tcp" "445/tcp") # Standard Samba ports
  local rules_needed=false # Flag to indicate if firewall rules need to be added
  
  # Check if UFW rules for Samba ports are already in place
  for port in "${ports[@]}"; do
    if ! ufw status | grep -q "$port.*ALLOW"; then
      rules_needed=true
      break
    fi
  done
  
  # Add UFW rules if needed
  if [[ "$rules_needed" == true ]]; then
    retry_command "ufw allow Samba" || log_fatal "Failed to configure firewall for Samba" # Allow Samba service by name
    for port in "${ports[@]}"; do
      retry_command "ufw allow $port" || log_fatal "Failed to allow $port for Samba" # Allow specific ports
    done
    log_info "Updated firewall to allow Samba traffic"
  else
    log_info "Samba firewall rules already set, skipping"
  fi
}

# Main execution
# =====================================================================================
# Function: main
# Description: Main execution flow for the Samba setup script.
#              It orchestrates the installation of Samba packages, configuration of
#              Samba users, creation and permission setting for shared directories,
#              configuration of `smb.conf`, restarting Samba services, and
#              configuration of firewall rules.
# Arguments:
#   None.
# Returns:
#   Exits with status 0 on successful completion.
# =====================================================================================
main() {
  install_samba # Install Samba packages
  configure_samba_user # Configure Samba user
  configure_samba_shares # Configure Samba share mount points and permissions
  configure_samba_config # Configure Samba global settings and shares in smb.conf
  
  # Restart Samba services and verify their active status
  retry_command "systemctl restart smbd nmbd" || log_fatal "Failed to restart Samba services"
  if ! systemctl is-active --quiet smbd || ! systemctl is-active --quiet nmbd; then
    log_fatal "Samba services are not active after restart."
  fi
  log_info "Restarted Samba services (smbd, nmbd)"
  
  configure_samba_firewall # Configure firewall for Samba
  
  log_info "Successfully completed hypervisor_feature_setup_samba.sh"
  exit 0
}

main "$@" # Call the main function to execute the script

log_info "Successfully completed hypervisor_feature_setup_samba.sh"
exit 0