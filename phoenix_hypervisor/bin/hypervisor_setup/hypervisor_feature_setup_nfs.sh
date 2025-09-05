#!/bin/bash

# File: hypervisor_feature_setup_nfs.sh
# Description: Configures NFS server and exports for Proxmox VE, reading configuration from hypervisor_config.json.
# Version: 1.0.0
# Author: Roo (AI Architect)

# Source common utilities
source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh

# Ensure script is run as root
check_root

log_info "Starting NFS server and exports setup."

# Parse command-line arguments
NO_REBOOT=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-reboot)
      NO_REBOOT=true
      shift
      ;;
    *)
      log_fatal "Unknown option $1"
      ;;
  esac
done

# install_nfs_packages: Installs required NFS packages
# Args: None
# Returns: 0 on success, 1 on failure
install_nfs_packages() {
  log_info "Installing NFS packages..."
  retry_command "apt-get update" || log_fatal "Failed to update package list"
  retry_command "apt-get install -y nfs-kernel-server nfs-common ufw" || log_fatal "Failed to install NFS packages"
  log_info "NFS packages installed"
}

# get_server_ip: Retrieves server IP in configured subnet
# Args: None
# Returns: Server IP or exits on failure
get_server_ip() {
  local subnet=$(jq -r '.network.interfaces.address // "10.0.0.0/24"' "$HYPERVISOR_CONFIG_FILE")
  if ! check_interface_in_subnet "$subnet"; then
    log_fatal "No network interface found in subnet $subnet"
  fi
  local ip
  ip=$(ip addr show | grep -E "inet.*$(echo "$subnet" | cut -d'/' -f1)" | awk '{print $2}' | cut -d'/' -f1 | head -1)
  if [[ -z "$ip" ]]; then
    log_fatal "Failed to determine server IP in subnet $subnet"
  fi
  echo "$ip"
}

# configure_nfs_exports: Configures NFS exports for ZFS datasets
# Args: None
# Returns: 0 on success, 1 on failure
configure_nfs_exports() {
  log_info "Configuring NFS exports..."
  local subnet=$(jq -r '.network.interfaces.address // "10.0.0.0/24"' "$HYPERVISOR_CONFIG_FILE")
  local exports_file="/etc/exports"

  # Backup exports file
  if [[ -f "$exports_file" ]]; then
    cp "$exports_file" "$exports_file.bak.$(date +%F_%H-%M-%S)" || log_fatal "Failed to backup $exports_file"
    log_info "Backed up $exports_file"
  fi

  # Clear exports file
  : > "$exports_file" || log_fatal "Failed to clear $exports_file"

  local nfs_shares_config
  nfs_shares_config=$(jq -c '.nfs_shares[]' "$HYPERVISOR_CONFIG_FILE")
  local configured_exports=0

  for share_json in $nfs_shares_config; do
    local path=$(echo "$share_json" | jq -r '.path')
    local clients_array=($(echo "$share_json" | jq -r '.clients[]'))
    local options_array=($(echo "$share_json" | jq -r '.options[]'))

    local options_str=$(IFS=,; echo "${options_array[*]}")
    local clients_str=$(IFS=,; echo "${clients_array[*]}")

    if [[ -z "$path" || -z "$clients_str" ]]; then
      log_warn "Skipping NFS share due to missing path or clients in configuration: $share_json"
      continue
    fi

    # Ensure the directory exists
    mkdir -p "$path" || log_fatal "Failed to create directory for NFS export: $path"

    # Add export
    if grep -q "^$path " "$exports_file"; then
      log_warn "Export line for $path already exists in $exports_file, skipping addition"
    else
      echo "$path $clients_str($options_str)" >> "$exports_file" || log_fatal "Failed to add $path to $exports_file"
      log_info "Added NFS export for $path with clients $clients_str and options $options_str"
      configured_exports=$((configured_exports + 1))
    fi
  done

  if [[ "$configured_exports" -eq 0 ]]; then
    log_warn "No NFS exports configured based on hypervisor_config.json."
  fi

  # Restart NFS service
  log_info "Refreshing and restarting NFS exports/services..."
  retry_command "exportfs -ra" || log_fatal "Failed to refresh NFS exports (exportfs -ra)"
  retry_command "systemctl restart nfs-server nfs-kernel-server 2>/dev/null || systemctl restart nfs-kernel-server" || log_fatal "Failed to restart NFS service"
  log_info "NFS exports configured and service restarted"
}

# configure_nfs_firewall: Configures firewall for NFS
# Args: None
# Returns: 0 on success, 1 on failure
configure_nfs_firewall() {
  log_info "Configuring firewall for NFS..."
  local subnet=$(jq -r '.network.interfaces.address // "10.0.0.0/24"' "$HYPERVISOR_CONFIG_FILE")
  
  if ! retry_command "ufw allow from $subnet to any port nfs"; then
    log_warn "Failed to allow NFS service in firewall (ufw allow nfs). Trying fallback to specific ports..."
    retry_command "ufw allow from $subnet to any port 111" || log_fatal "Failed to allow port 111 (rpcbind) in firewall"
    retry_command "ufw allow from $subnet to any port 2049" || log_fatal "Failed to allow port 2049 (nfs) in firewall"
  fi
  log_info "Firewall configured for NFS"
}

# add_nfs_storage: Adds NFS storage to Proxmox
# Args: None
# Returns: 0 on success, 1 on failure
add_nfs_storage() {
  log_info "Adding NFS storage to Proxmox..."
  check_pvesm

  local server_ip
  server_ip=$(get_server_ip)
  local nfs_shares_config
  nfs_shares_config=$(jq -c '.nfs_shares[]' "$HYPERVISOR_CONFIG_FILE")
  local added_proxmox_storage=0

  for share_json in $nfs_shares_config; do
    local path=$(echo "$share_json" | jq -r '.path')
    local content_type="images,iso,vztmpl,backup,snippets" # Default content types for NFS
    local storage_name="nfs-$(basename "$path" | tr '/' '-')" # Derive storage name from path

    # Check if Proxmox storage already exists
    if pvesm status | grep -q "^$storage_name "; then
      log_info "Proxmox storage $storage_name already exists, skipping addition."
      continue
    fi

    log_info "Checking if export $path is available on $server_ip..."
    if ! showmount -e "$server_ip" | grep -q "$(echo "$path" | sed 's/\//\\\//g')"; then
      log_fatal "NFS export $path not available on $server_ip according to showmount. Check NFS server configuration."
    fi
    log_info "Confirmed export $path is available on $server_ip"

    local local_mount="/mnt/nfs/$storage_name"
    mkdir -p "$local_mount" || log_fatal "Failed to create local mount point $local_mount for Proxmox NFS storage"
    
    log_info "Adding NFS storage $storage_name to Proxmox..."
    retry_command "pvesm add nfs $storage_name --server $server_ip --export $path --content $content_type --path $local_mount --options vers=4,soft,timeo=30,retrans=3" || log_fatal "Failed to add NFS storage $storage_name using pvesm"
    log_info "Successfully added NFS storage $storage_name for $path at $local_mount with content $content_type"
    added_proxmox_storage=$((added_proxmox_storage + 1))
  done

  if [[ "$added_proxmox_storage" -eq 0 ]]; then
    log_warn "No NFS storage added to Proxmox based on hypervisor_config.json."
  fi
}

# Main execution
install_nfs_packages
configure_nfs_exports
configure_nfs_firewall
add_nfs_storage

if [[ "$NO_REBOOT" == false ]]; then
  log_info "Forcing reboot to apply NFS changes in 10 seconds. Press Ctrl+C to cancel"
  sleep 10
  reboot
else
  log_info "Reboot skipped due to --no-reboot flag. Please reboot manually to apply NFS changes"
fi

log_info "Successfully completed hypervisor_feature_setup_nfs.sh"
exit 0