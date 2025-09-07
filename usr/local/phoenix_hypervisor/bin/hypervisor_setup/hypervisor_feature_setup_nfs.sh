#!/bin/bash

# File: hypervisor_feature_setup_nfs.sh
# Description: Configures an NFS server and its exports on a Proxmox VE host.
#              This script reads NFS share definitions from `hypervisor_config.json`,
#              installs necessary packages, configures `/etc/exports`, sets up firewall
#              rules, and integrates the NFS shares as storage within Proxmox VE.
#              A system reboot is recommended after execution.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq, apt-get,
#               nfs-kernel-server, nfs-common, ufw, ip, awk, exportfs, systemctl,
#               pvesm, showmount, mkdir, cp, grep, sed.
# Inputs:
#   --no-reboot: Optional flag to skip the automatic reboot after configuration.
#   Configuration values from HYPERVISOR_CONFIG_FILE: .network.interfaces.address,
#   .nfs_shares[] (path, clients[], options[]).
# Outputs:
#   NFS package installation logs, `/etc/exports` file modifications, UFW firewall
#   rule additions, Proxmox VE storage additions, log messages to stdout and
#   MAIN_LOG_FILE, exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# Ensure script is run as root
check_root

log_info "Starting NFS server and exports setup."

# Get the configuration file path from the first argument
if [ -z "$1" ]; then
    log_fatal "Configuration file path not provided."
fi
HYPERVISOR_CONFIG_FILE="$1"

# Parse command-line arguments

# install_nfs_packages: Installs required NFS packages
# Args: None
# Returns: 0 on success, 1 on failure
# =====================================================================================
# Function: install_nfs_packages
# Description: Installs the necessary NFS server and client packages, along with UFW.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if package installation fails.
# =====================================================================================
install_nfs_packages() {
  log_info "Installing NFS packages..."
  retry_command "apt-get update" || log_fatal "Failed to update package list" # Update package lists
  retry_command "apt-get install -y nfs-kernel-server nfs-common ufw" || log_fatal "Failed to install NFS packages" # Install NFS packages and UFW
  log_info "NFS packages installed"
}

# get_server_ip: Retrieves server IP in configured subnet
# Args: None
# Returns: Server IP or exits on failure
# =====================================================================================
# Function: get_server_ip
# Description: Retrieves the IP address of the server within the configured subnet.
# Arguments:
#   None (uses global HYPERVISOR_CONFIG_FILE).
# Returns:
#   The server's IP address on success, or exits with a fatal error if no interface
#   is found in the subnet or IP determination fails.
# =====================================================================================
get_server_ip() {
  # Directly read the configured IP address from the config file.
  local ip_with_cidr=$(jq -r '.network.interfaces.address // ""' "$HYPERVISOR_CONFIG_FILE")
  
  # Check if an IP address was successfully determined
  if [[ -z "$ip_with_cidr" ]]; then
    log_fatal "Failed to determine server IP from configuration file."
  fi
  
  # Remove the CIDR notation (e.g., /24) to get the pure IP address.
  local ip=$(echo "$ip_with_cidr" | cut -d'/' -f1)
  
  log_info "Using configured server IP for NFS: $ip"
  echo "$ip" # Output the determined IP address
}

# configure_nfs_exports: Configures NFS exports for ZFS datasets
# Args: None
# Returns: 0 on success, 1 on failure
# =====================================================================================
# Function: configure_nfs_exports
# Description: Configures NFS exports based on definitions in `hypervisor_config.json`.
#              It backs up the existing `/etc/exports` file, clears it, then adds
#              new export entries for each defined NFS share, ensuring directories exist.
#              Finally, it restarts the NFS services.
# Arguments:
#   None (uses global HYPERVISOR_CONFIG_FILE).
# Returns:
#   None. Exits with a fatal error if file operations, directory creation, or
#   NFS service restarts fail.
# =====================================================================================
configure_nfs_exports() {
  log_info "Configuring NFS exports..."
  local subnet=$(jq -r '.network.interfaces.address // "10.0.0.0/24"' "$HYPERVISOR_CONFIG_FILE") # Retrieve subnet from config
  local exports_file="/etc/exports" # Path to the NFS exports configuration file

  # Backup exports file
  # Backup the existing exports file if it exists
  if [[ -f "$exports_file" ]]; then
    cp "$exports_file" "$exports_file.bak.$(date +%F_%H-%M-%S)" || log_fatal "Failed to backup $exports_file"
    log_info "Backed up $exports_file"
  fi

  # Clear exports file
  : > "$exports_file" || log_fatal "Failed to clear $exports_file"

  local nfs_shares_config # Variable to store NFS shares configuration
  nfs_shares_config=$(jq -c '.nfs.exports[]' "$HYPERVISOR_CONFIG_FILE") # Retrieve NFS shares array from config
  local configured_exports=0 # Counter for successfully configured exports

  # Iterate through each NFS share defined in the configuration
  for share_json in $nfs_shares_config; do
    local path=$(echo "$share_json" | jq -r '.path') # Export path
    local clients_array=($(echo "$share_json" | jq -r '.clients[]')) # Array of allowed clients
    local options_array=($(echo "$share_json" | jq -r '.options[]')) # Array of export options

    local options_str=$(IFS=,; echo "${options_array[*]}") # Convert options array to comma-separated string
    local clients_str=$(IFS=,; echo "${clients_array[*]}") # Convert clients array to comma-separated string

    # Skip if path or clients are missing in the configuration
    if [[ -z "$path" || -z "$clients_str" ]]; then
      log_warn "Skipping NFS share due to missing path or clients in configuration: $share_json"
      continue
    fi

    # Ensure the directory exists
    # Ensure the directory for the NFS export exists
    mkdir -p "$path" || log_fatal "Failed to create directory for NFS export: $path"

    # Add export
    # Add the NFS export entry to the exports file if it doesn't already exist
    if grep -q "^$path " "$exports_file"; then
      log_warn "Export line for $path already exists in $exports_file, skipping addition"
    else
      echo "$path $clients_str($options_str)" >> "$exports_file" || log_fatal "Failed to add $path to $exports_file"
      log_info "Added NFS export for $path with clients $clients_str and options $options_str"
      configured_exports=$((configured_exports + 1)) # Increment counter
    fi
  done

  # Warn if no NFS exports were configured
  if [[ "$configured_exports" -eq 0 ]]; then
    log_warn "No NFS exports configured based on hypervisor_config.json."
  fi

  # Restart NFS service
  # Refresh NFS exports and restart NFS services
  log_info "Refreshing and restarting NFS exports/services..."
  retry_command "exportfs -ra" || log_fatal "Failed to refresh NFS exports (exportfs -ra)" # Refresh exports
  retry_command "systemctl restart nfs-server nfs-kernel-server 2>/dev/null || systemctl restart nfs-kernel-server" || log_fatal "Failed to restart NFS service" # Restart NFS service
  log_info "NFS exports configured and service restarted"
}

# configure_nfs_firewall: Configures firewall for NFS
# Args: None
# Returns: 0 on success, 1 on failure
# =====================================================================================
# Function: configure_nfs_firewall
# Description: Configures the Uncomplicated Firewall (UFW) to allow NFS traffic
#              from the configured subnet. It attempts to allow the 'nfs' service
#              and falls back to allowing specific NFS ports if the service rule fails.
# Arguments:
#   None (uses global HYPERVISOR_CONFIG_FILE).
# Returns:
#   None. Exits with a fatal error if firewall rules cannot be applied.
# =====================================================================================
configure_nfs_firewall() {
  log_info "Configuring firewall for NFS..."
  local subnet=$(jq -r '.network.interfaces.address // "10.0.0.0/24"' "$HYPERVISOR_CONFIG_FILE") # Retrieve subnet from config
  
  # Attempt to allow NFS service by name in UFW
  if ! retry_command "ufw allow from $subnet to any port nfs"; then
    log_warn "Failed to allow NFS service in firewall (ufw allow nfs). Trying fallback to specific ports..."
    # Fallback to allowing specific NFS ports if service rule fails
    retry_command "ufw allow from $subnet to any port 111" || log_fatal "Failed to allow port 111 (rpcbind) in firewall"
    retry_command "ufw allow from $subnet to any port 2049" || log_fatal "Failed to allow port 2049 (nfs) in firewall"
  fi
  log_info "Firewall configured for NFS"
}

# add_nfs_storage: Adds NFS storage to Proxmox
# Args: None
# Returns: 0 on success, 1 on failure
# =====================================================================================
# Function: add_nfs_storage
# Description: Adds NFS shares as storage to Proxmox VE. It retrieves NFS share
#              definitions from `hypervisor_config.json`, checks for existing
#              Proxmox storage, verifies NFS exports, creates local mount points,
#              and then uses `pvesm add nfs` to integrate the storage.
# Arguments:
#   None (uses global HYPERVISOR_CONFIG_FILE).
# Returns:
#   None. Exits with a fatal error if `pvesm` is not available, NFS export is
#   not found, local mount point creation fails, or `pvesm add nfs` fails.
# =====================================================================================
add_nfs_storage() {
  log_info "Adding NFS storage to Proxmox..."
  # =====================================================================================
  # Function: check_pvesm
  # Description: Checks for the availability of the `pvesm` command.
  # =====================================================================================
  check_pvesm() {
    if ! command -v pvesm >/dev/null 2>&1; then
      log_fatal "pvesm command not found. This script must be run on a Proxmox VE host."
    fi
    log_info "Verified pvesm availability."
  }

  check_pvesm # Ensure pvesm command is available

  local server_ip # Variable to store the server's IP address
  server_ip=$(get_server_ip) # Get the server's IP in the configured subnet
  local nfs_shares_config # Variable to store NFS shares configuration
  nfs_shares_config=$(jq -c '.nfs.exports[]' "$HYPERVISOR_CONFIG_FILE") # Retrieve NFS shares array from config
  local added_proxmox_storage=0 # Counter for successfully added Proxmox storage entries

  # Iterate through each NFS share defined in the configuration
  for share_json in $nfs_shares_config; do
    local path=$(echo "$share_json" | jq -r '.path') # Export path
    local content_type="images,iso,vztmpl,backup,snippets" # Default content types for NFS storage in Proxmox
    local storage_name="nfs-$(basename "$path" | tr '/' '-')" # Derive a unique storage name from the path

    # Check if Proxmox storage already exists
    # Check if Proxmox storage with this name already exists
    if pvesm status | grep -q "^$storage_name "; then
      log_info "Proxmox storage $storage_name already exists, skipping addition."
      continue
    fi

    log_info "Checking if export $path is available on $server_ip..."
    # Verify that the NFS export is available on the server using `showmount`
    if ! showmount -e "$server_ip" | grep -q "$(echo "$path" | sed 's/\//\\\//g')"; then
      log_fatal "NFS export $path not available on $server_ip according to showmount. Check NFS server configuration."
    fi
    log_info "Confirmed export $path is available on $server_ip"

    local local_mount="/mnt/nfs/$storage_name" # Define local mount point for Proxmox
    mkdir -p "$local_mount" || log_fatal "Failed to create local mount point $local_mount for Proxmox NFS storage" # Create local mount point
    
    log_info "Adding NFS storage $storage_name to Proxmox..."
    # Add the NFS storage to Proxmox VE using `pvesm add nfs`
    retry_command "pvesm add nfs $storage_name --server $server_ip --export $path --content $content_type --path $local_mount --options vers=4,soft,timeo=30,retrans=3" || log_fatal "Failed to add NFS storage $storage_name using pvesm"
    log_info "Successfully added NFS storage $storage_name for $path at $local_mount with content $content_type"
    added_proxmox_storage=$((added_proxmox_storage + 1)) # Increment counter
  done

  # Warn if no NFS storage entries were added to Proxmox
  if [[ "$added_proxmox_storage" -eq 0 ]]; then
    log_warn "No NFS storage added to Proxmox based on hypervisor_config.json."
  fi
}

# Main execution
# =====================================================================================
# Function: main
# Description: Main execution flow for the NFS setup script.
#              It orchestrates the installation of NFS packages, configuration of
#              exports and firewall rules, and integration of NFS storage with Proxmox VE.
#              It also handles post-configuration reboot recommendations.
# Arguments:
#   None (uses global NO_REBOOT).
# Returns:
#   Exits with status 0 on successful completion.
# =====================================================================================
main() {
  install_nfs_packages # Install required NFS packages
  configure_nfs_exports # Configure NFS exports
  configure_nfs_firewall # Configure firewall for NFS
  add_nfs_storage # Add NFS storage to Proxmox

  # Handle system reboot based on the --no-reboot flag
  log_info "A reboot is recommended to apply NFS changes. Please reboot manually."
  
  log_info "Successfully completed hypervisor_feature_setup_nfs.sh"
  exit 0
}

main "$@" # Call the main function

log_info "Successfully completed hypervisor_feature_setup_nfs.sh"
exit 0