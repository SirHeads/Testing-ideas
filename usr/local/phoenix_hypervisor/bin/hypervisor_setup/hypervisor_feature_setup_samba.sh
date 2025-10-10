#!/bin/bash

# File: hypervisor_feature_setup_samba.sh
# Description: This script provides a comprehensive, declarative setup for a Samba file server on the Proxmox VE host.
#              It is a core component of the hypervisor's file sharing capabilities, designed to provide SMB/CIFS access
#              to shared resources. The script reads all of its configuration from the main `phoenix_hypervisor_config.json` file,
#              including share definitions and user access. It handles package installation, Samba user creation, generation
#              of the `/etc/samba/smb.conf` file, and firewall configuration. The entire process is idempotent.
#
# Dependencies:
#   - /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - `jq`: For parsing the JSON configuration file.
#   - `samba`, `smbclient`: Core Samba server and client packages.
#   - `ufw`: The Uncomplicated Firewall for managing access.
#   - Standard system utilities: `pdbedit`, `smbpasswd`, `systemctl`, `cp`, `grep`.
#
# Inputs:
#   - A path to a JSON configuration file (e.g., `phoenix_hypervisor_config.json`) passed as the first command-line argument.
#   - The JSON file is expected to contain:
#     - `.samba.user`: The system user to be configured for Samba access.
#     - `.network.workgroup`: The workgroup name for the Samba server.
#     - `.samba.shares[]`: An array of Samba share objects, each with:
#       - `name`: The name of the share.
#       - `path`: The directory path on the host to be shared.
#       - `browsable`, `read_only`, `guest_ok`: Boolean flags for share options.
#       - `valid_users[]`: An array of users permitted to access the share.
#
# Outputs:
#   - Installs Samba server packages.
#   - Creates and configures the `/etc/samba/smb.conf` file.
#   - Creates a Samba user and sets their password.
#   - Configures UFW firewall rules to allow Samba traffic.
#   - Logs its progress to standard output.
#   - Exit Code: 0 on success, non-zero on failure.

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# Ensure script is run as root
check_root

log_info "Starting Samba server and shares setup."

# Get the configuration file path from the first argument
if [ -z "$1" ]; then
    log_fatal "Configuration file path not provided."
fi
HYPERVISOR_CONFIG_FILE="$1"

# Read Samba configuration from the declarative JSON file.
log_info "Reading Samba configuration from $HYPERVISOR_CONFIG_FILE..."
SMB_USER=$(jq -r '.samba.user // "heads"' "$HYPERVISOR_CONFIG_FILE")
NETWORK_NAME=$(jq -r '.network.workgroup // "WORKGROUP"' "$HYPERVISOR_CONFIG_FILE")
MOUNT_POINT_BASE=$(jq -r '.mount_point_base // "/mnt/pve"' "$HYPERVISOR_CONFIG_FILE")

# Pre-flight check to ensure the underlying system user for Samba already exists.
if ! id "$SMB_USER" >/dev/null 2>&1; then
  log_fatal "System user $SMB_USER does not exist. Please create it first."
fi
log_info "Verified that Samba system user $SMB_USER exists"

# Validate the workgroup name format.
if [[ ! "$NETWORK_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  log_fatal "Network name '$NETWORK_NAME' must contain only letters, numbers, hyphens, or underscores."
fi
log_info "Set Samba workgroup to $NETWORK_NAME"

# =====================================================================================
# Function: install_samba
# Description: Installs the Samba server and client packages if they are not already present.
# =====================================================================================
install_samba() {
  if ! check_package samba; then
    retry_command "apt-get update" || log_fatal "Failed to update package lists"
    retry_command "apt-get install -y samba samba-common-bin smbclient" || log_fatal "Failed to install Samba"
    log_info "Installed Samba"
  else
    log_info "Samba already installed, skipping installation"
  fi
}

# =====================================================================================
# Function: configure_samba_user
# Description: Configures the specified system user for Samba access by setting their
#              password in the Samba database. This function is idempotent.
# =====================================================================================
configure_samba_user() {
  log_info "Configuring Samba user: $SMB_USER"

  # TODO: This password should be read from a secure location, not hardcoded.
  local smb_password="headssamba"

  # Idempotency check: Only create the Samba user if they don't exist in the pdbedit database.
  if ! pdbedit -L | grep -q "^$SMB_USER:"; then
    log_info "Samba user $SMB_USER does not exist. Creating user..."
    # Create the Samba user non-interactively by piping the password twice.
    if ! (echo "$smb_password"; echo "$smb_password") | smbpasswd -s -a "$SMB_USER" >/dev/null 2>&1; then
      log_fatal "Failed to create Samba user $SMB_USER."
    fi
    log_info "Successfully created Samba user $SMB_USER."
  else
    log_info "Samba user $SMB_USER already exists. Skipping creation."
  fi
}

# =====================================================================================
# Function: configure_samba_shares
# Description: Creates the physical directories for the Samba shares on the filesystem
#              and sets the appropriate ownership and permissions.
# =====================================================================================
configure_samba_shares() {
  log_info "Configuring Samba share mount points and permissions..."
  mkdir -p "$MOUNT_POINT_BASE" || log_fatal "Failed to create $MOUNT_POINT_BASE"

  # Iterate through each Samba share defined in the configuration.
  jq -c '.samba.shares[]' "$HYPERVISOR_CONFIG_FILE" | while IFS= read -r share_json; do
    local share_name=$(echo "$share_json" | jq -r '.name')
    local path=$(echo "$share_json" | jq -r '.path')
    
    if [[ -z "$path" ]]; then
      log_warn "Skipping Samba share '$share_name' due to missing path in configuration."
      continue
    fi

    # Ensure the directory for the Samba share exists.
    mkdir -p "/$path" || log_fatal "Failed to create directory for Samba share: /$path"

    # Set ownership and permissions for the shared directory.
    retry_command "chown $SMB_USER:$SMB_USER \"/$path\"" || log_fatal "Failed to set ownership for /$path"
    retry_command "chmod 770 \"/$path\"" || log_fatal "Failed to set permissions for /$path"
    log_info "Created and configured mountpoint /$path for Samba share '$share_name'"
  done
}

# =====================================================================================
# Function: configure_samba_config
# Description: Generates the `/etc/samba/smb.conf` file from scratch based on the
#              declarative configuration. It sets up the [global] section and then
#              appends a section for each defined share.
# =====================================================================================
configure_samba_config() {
  log_info "Configuring Samba global settings and shares in /etc/samba/smb.conf..."
  local smb_conf_file="/etc/samba/smb.conf"

  # Backup the existing smb.conf file.
  if [[ -f "$smb_conf_file" ]]; then
    cp "$smb_conf_file" "$smb_conf_file.bak.$(date +%F_%H-%M-%S)" || log_fatal "Failed to back up $smb_conf_file"
    log_info "Backed up $smb_conf_file"
  fi

  # Write a modern, streamlined global Samba settings section to smb.conf.
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

  # Iterate through each Samba share and append its configuration to smb.conf.
  jq -c '.samba.shares[]' "$HYPERVISOR_CONFIG_FILE" | while IFS= read -r share_json; do
    local share_name=$(echo "$share_json" | jq -r '.name')
    local path=$(echo "$share_json" | jq -r '.path')
    local browsable=$(echo "$share_json" | jq -r '.browsable // true')
    local read_only=$(echo "$share_json" | jq -r '.read_only // false')
    local guest_ok=$(echo "$share_json" | jq -r '.guest_ok // false')
    local valid_users_array=($(echo "$share_json" | jq -r '.valid_users[]'))
    local valid_users_str=$(IFS=,; echo "${valid_users_array[*]}")

    # Convert boolean settings from JSON to "yes" or "no" strings required by smb.conf.
    local browsable_str=$([ "$browsable" == "true" ] && echo "yes" || echo "no")
    local writable_str=$([ "$read_only" == "false" ] && echo "yes" || echo "no")
    local guest_ok_str=$([ "$guest_ok" == "true" ] && echo "yes" || echo "no")

    # Append the configuration block for the individual share.
    cat << EOF >> "$smb_conf_file"

[$share_name]
   path = /$path
   writable = $writable_str
   browsable = $browsable_str
   guest ok = $guest_ok_str
   valid users = $valid_users_str
   create mask = 0770
   directory mask = 0770
   force create mode = 0770
   force directory mode = 0770
EOF
    log_info "Added Samba share '$share_name' for path /$path to $smb_conf_file"
  done
  log_info "Samba shares configured."
}

# =====================================================================================
# Function: configure_samba_firewall
# Description: Configures the Uncomplicated Firewall (UFW) to allow the standard ports
#              required for Samba to function.
# =====================================================================================
configure_samba_firewall() {
  log_info "Samba firewall configuration is now managed by hypervisor_feature_setup_firewall.sh. Skipping."
}

# =====================================================================================
# Function: main
# Description: Main execution flow for the Samba setup script. It orchestrates all the
#              necessary steps to set up a fully functional Samba server based on the
#              declarative configuration.
# =====================================================================================
main() {
  install_samba
  configure_samba_user
  configure_samba_shares
  configure_samba_config
  
  # Restart Samba services to apply all configuration changes.
  retry_command "systemctl restart smbd nmbd" || log_fatal "Failed to restart Samba services"
  if ! systemctl is-active --quiet smbd || ! systemctl is-active --quiet nmbd; then
    log_fatal "Samba services are not active after restart."
  fi
  log_info "Restarted Samba services (smbd, nmbd)"
  
  configure_samba_firewall
  
  log_info "Successfully completed hypervisor_feature_setup_samba.sh"
  exit 0
}

main "$@"