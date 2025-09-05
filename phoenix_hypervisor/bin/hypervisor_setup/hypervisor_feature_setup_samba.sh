#!/bin/bash

# File: hypervisor_feature_setup_samba.sh
# Description: Configures Samba file server on Proxmox VE with shares for ZFS datasets and user authentication,
#              reading configuration from hypervisor_config.json.
# Version: 1.0.0
# Author: Roo (AI Architect)

# Source common utilities
source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh

# Ensure script is run as root
check_root

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

# Validate Samba user
if ! id "$SMB_USER" >/dev/null 2>&1; then
  log_fatal "System user $SMB_USER does not exist. Please create it first."
fi
log_info "Verified that Samba system user $SMB_USER exists"

# Validate network name
if [[ ! "$NETWORK_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  log_fatal "Network name '$NETWORK_NAME' must contain only letters, numbers, hyphens, or underscores."
fi
log_info "Set Samba workgroup to $NETWORK_NAME"

# install_samba: Installs Samba packages if not present
# Args: None
# Returns: 0 on success, 1 on failure
install_samba() {
  if ! check_package samba; then
    retry_command "apt-get update" || log_fatal "Failed to update package lists"
    retry_command "apt-get install -y samba samba-common-bin smbclient" || log_fatal "Failed to install Samba"
    log_info "Installed Samba"
  else
    log_info "Samba already installed, skipping installation"
  fi
}

# configure_samba_user: Sets Samba password for the configured user
# Args: None (uses global SMB_USER)
# Returns: 0 on success, 1 on failure
configure_samba_user() {
  log_info "Configuring Samba user: $SMB_USER"
  if ! pdbedit -L | grep -q "^$SMB_USER:"; then
    log_warn "Samba user $SMB_USER does not exist. Please set the Samba password manually using 'smbpasswd -a $SMB_USER'."
    # In a fully automated scenario, we would pipe a password here.
    # For 1:1 porting, we're reflecting the original's interactive nature or pre-set password assumption.
    # If a password hash was available and suitable for smbpasswd, it would be used here.
  else
    log_info "Samba user $SMB_USER already exists. Skipping password setup (assuming it's already set or will be set manually)."
  fi
}

# configure_samba_shares: Creates mount points for Samba shares and sets permissions
# Args: None
# Returns: 0 on success, 1 on failure
configure_samba_shares() {
  log_info "Configuring Samba share mount points and permissions..."
  mkdir -p "$MOUNT_POINT_BASE" || log_fatal "Failed to create $MOUNT_POINT_BASE"

  local samba_shares_config
  samba_shares_config=$(jq -c '.samba_shares[]' "$HYPERVISOR_CONFIG_FILE")

  for share_json in $samba_shares_config; do
    local share_name=$(echo "$share_json" | jq -r '.name')
    local path=$(echo "$share_json" | jq -r '.path')
    local valid_users_array=($(echo "$share_json" | jq -r '.valid_users[]'))
    local valid_users_str=$(IFS=,; echo "${valid_users_array[*]}")

    if [[ -z "$path" ]]; then
      log_warn "Skipping Samba share '$share_name' due to missing path in configuration."
      continue
    fi

    # Ensure the directory exists
    mkdir -p "$path" || log_fatal "Failed to create directory for Samba share: $path"

    # Set ownership and permissions
    retry_command "chown $SMB_USER:$SMB_USER \"$path\"" || log_fatal "Failed to set ownership for $path"
    retry_command "chmod 770 \"$path\"" || log_fatal "Failed to set permissions for $path"
    log_info "Created and configured mountpoint $path for Samba share '$share_name'"
  done
}

# configure_samba_config: Configures Samba shares in smb.conf
# Args: None
# Returns: 0 on success, 1 on failure
configure_samba_config() {
  log_info "Configuring Samba global settings and shares in /etc/samba/smb.conf..."
  local smb_conf_file="/etc/samba/smb.conf"

  if [[ -f "$smb_conf_file" ]]; then
    cp "$smb_conf_file" "$smb_conf_file.bak.$(date +%F_%H-%M-%S)" || log_fatal "Failed to back up $smb_conf_file"
    log_info "Backed up $smb_conf_file"
  fi

  # Start with global settings
  cat << EOF > "$smb_conf_file"
[global]
   workgroup = $NETWORK_NAME
   server string = %h Proxmox Samba Server
   security = user
   log file = /var/log/samba/log.%m
   max log size = 1000
   syslog = 0
   panic action = /usr/share/samba/panic-action %d
   server role = standalone server
   passdb backend = tdbsam
   obey pam restrictions = yes
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
   pam password change = yes
   map to guest = bad user
   dns proxy = no
EOF

  local samba_shares_config
  samba_shares_config=$(jq -c '.samba_shares[]' "$HYPERVISOR_CONFIG_FILE")

  for share_json in $samba_shares_config; do
    local share_name=$(echo "$share_json" | jq -r '.name')
    local path=$(echo "$share_json" | jq -r '.path')
    local browsable=$(echo "$share_json" | jq -r '.browsable // true')
    local read_only=$(echo "$share_json" | jq -r '.read_only // false')
    local guest_ok=$(echo "$share_json" | jq -r '.guest_ok // false')
    local valid_users_array=($(echo "$share_json" | jq -r '.valid_users[]'))
    local valid_users_str=$(IFS=,; echo "${valid_users_array[*]}")

    # Convert boolean to yes/no
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
configure_samba_firewall() {
  log_info "Configuring firewall for Samba..."
  local ports=("137/udp" "138/udp" "139/tcp" "445/tcp")
  local rules_needed=false
  for port in "${ports[@]}"; do
    if ! ufw status | grep -q "$port.*ALLOW"; then
      rules_needed=true
      break
    fi
  done
  if [[ "$rules_needed" == true ]]; then
    retry_command "ufw allow Samba" || log_fatal "Failed to configure firewall for Samba"
    for port in "${ports[@]}"; do
      retry_command "ufw allow $port" || log_fatal "Failed to allow $port for Samba"
    done
    log_info "Updated firewall to allow Samba traffic"
  else
    log_info "Samba firewall rules already set, skipping"
  fi
}

# Main execution
install_samba
configure_samba_user
configure_samba_shares
configure_samba_config
retry_command "systemctl restart smbd nmbd" || log_fatal "Failed to restart Samba services"
if ! systemctl is-active --quiet smbd || ! systemctl is-active --quiet nmbd; then
  log_fatal "Samba services are not active after restart."
fi
log_info "Restarted Samba services (smbd, nmbd)"
configure_samba_firewall

log_info "Successfully completed hypervisor_feature_setup_samba.sh"
exit 0