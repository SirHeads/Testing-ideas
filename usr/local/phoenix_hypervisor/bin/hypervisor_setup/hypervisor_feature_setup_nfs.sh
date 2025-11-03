#!/bin/bash

# File: hypervisor_feature_setup_nfs.sh
# Description: This script provides a comprehensive, declarative setup for an NFS server on the Proxmox VE host.
#              It is a core component of the hypervisor's file sharing capabilities. The script reads its configuration
#              from the main `phoenix_hypervisor_config.json` file to install necessary packages, configure NFS exports
#              in `/etc/exports`, manage firewall rules with UFW, and finally, integrate the NFS shares as usable
#              storage resources within Proxmox VE itself. The entire process is designed to be idempotent, ensuring
#              that it can be run multiple times to enforce the desired state without causing errors.
#
# Dependencies:
#   - /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - `jq`: For parsing the JSON configuration file.
#   - `nfs-kernel-server`, `nfs-common`: Core NFS server packages.
#   - `ufw`: The Uncomplicated Firewall for managing access.
#   - `pvesm`: The Proxmox VE Storage Manager for integrating the NFS shares.
#   - Standard system utilities: `ip`, `awk`, `exportfs`, `systemctl`, `showmount`, `mkdir`, `cp`, `grep`, `sed`.
#
# Inputs:
#   - A path to a JSON configuration file (e.g., `phoenix_hypervisor_config.json`) passed as the first command-line argument.
#   - The JSON file is expected to contain:
#     - `.network.interfaces.address`: The subnet used for NFS client access.
#     - `.nfs.exports[]`: An array of NFS share objects, each with:
#       - `path`: The directory path on the host to be exported.
#       - `clients[]`: An array of client IP addresses or subnets.
#       - `options[]`: An array of NFS export options (e.g., "rw", "sync").
#
# Outputs:
#   - Installs NFS server packages.
#   - Creates and configures the `/etc/exports` file.
#   - Configures UFW firewall rules to allow NFS traffic.
#   - Adds the configured NFS shares as storage resources in Proxmox VE.
#   - Logs its progress to standard output.
#   - Exit Code: 0 on success, non-zero on failure.

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# Ensure script is run as root
check_root

log_info "Starting NFS server and exports setup."

# Get the configuration file path from the first argument
# The HYPERVISOR_CONFIG_FILE is passed as the first argument by the hypervisor-manager.
if [ -z "$1" ]; then
    log_fatal "Configuration file path not provided."
fi
HYPERVISOR_CONFIG_FILE="$1"

# =====================================================================================
# Function: install_nfs_packages
# Description: Ensures that all necessary packages for running an NFS server and managing
#              the firewall are installed on the system.
# =====================================================================================
install_nfs_packages() {
  log_info "Installing NFS packages..."
  retry_command "apt-get install -y nfs-kernel-server nfs-common" || log_fatal "Failed to install NFS packages"
  log_info "NFS packages installed"
}

# =====================================================================================
# Function: configure_nfs_locking
# Description: Ensures the NFS locking daemon (statd) is enabled, which is
#              necessary for stable NFS mounts from clients.
# =====================================================================================
configure_nfs_locking() {
  log_info "Configuring NFS locking..."
  local nfs_common_config="/etc/default/nfs-common"
  
  if grep -q "NEED_STATD=yes" "$nfs_common_config"; then
    log_info "NFS locking (statd) is already enabled."
  else
    log_info "Enabling NFS locking (statd)..."
    echo "NEED_STATD=yes" >> "$nfs_common_config" || log_fatal "Failed to enable NFS locking in $nfs_common_config"
  fi
  
  # Unmask the service before trying to restart it.
  log_info "Unmasking nfs-common service..."
  systemctl unmask nfs-common.service || log_warn "Failed to unmask nfs-common service. This may not be an error if it was not masked."
  systemctl daemon-reload || log_warn "Failed to reload systemd daemon. The unmask operation may not take effect immediately."

  # Restart the dependent services to apply the change.
  retry_command "systemctl restart nfs-common" || log_warn "Failed to restart nfs-common service."
  retry_command "systemctl restart nfs-kernel-server" || log_warn "Failed to restart nfs-kernel-server."
  log_info "NFS locking configured and services restarted."
}

# =====================================================================================
# Function: get_server_ip
# Description: Retrieves the primary IP address of the hypervisor from the declarative
#              configuration file. This IP is used as the server address when adding
#              the NFS shares to Proxmox storage.
# =====================================================================================
get_server_ip() {
  # Directly read the configured IP address from the config file.
  local ip_with_cidr=$(jq -r '.network.interfaces.address // ""' "$HYPERVISOR_CONFIG_FILE")
  
  if [[ -z "$ip_with_cidr" ]]; then
    log_fatal "Failed to determine server IP from configuration file."
  fi
  
  # Remove the CIDR notation (e.g., /24) to get the pure IP address.
  local ip=$(echo "$ip_with_cidr" | cut -d'/' -f1)
  
  log_info "Using configured server IP for NFS: $ip"
  echo "$ip"
}

# =====================================================================================
# Function: configure_nfs_exports
# Description: Configures the `/etc/exports` file based on the `nfs.exports` array in
#              the JSON configuration. It backs up the existing file, then iterates through
#              the defined shares, creating directories and writing the export lines.
#              The function is idempotent and will not create duplicate entries.
# =====================================================================================
configure_nfs_exports() {
  log_info "Configuring NFS exports..."
  local subnet=$(jq -r '.network.interfaces.address // "10.0.0.0/24"' "$HYPERVISOR_CONFIG_FILE")
  local exports_file="/etc/exports"

  # Backup the existing exports file before making changes.
  if [[ -f "$exports_file" ]]; then
    cp "$exports_file" "$exports_file.bak.$(date +%F_%H-%M-%S)" || log_fatal "Failed to backup $exports_file"
    log_info "Backed up $exports_file"
  fi

  # Start with a clean exports file to ensure the declarative state is accurately reflected.
  : > "$exports_file" || log_fatal "Failed to clear $exports_file"

  local nfs_shares_config
  nfs_shares_config=$(jq -c '.nfs.exports[]' "$HYPERVISOR_CONFIG_FILE")
  local configured_exports=0

  # Iterate through each NFS share defined in the configuration.
  for share_json in $nfs_shares_config; do
    local path=$(echo "$share_json" | jq -r '.path')
    local clients_array=($(echo "$share_json" | jq -r '.clients[]'))
    local options_array=($(echo "$share_json" | jq -r '.options[]'))

    local options_str=$(IFS=,; echo "${options_array[*]}")

    if [[ -z "$path" || ${#clients_array[@]} -eq 0 ]]; then
      log_warn "Skipping NFS share due to missing path or clients in configuration: $share_json"
      continue
    fi

    # Ensure the directory for the NFS export exists.
    mkdir -p "$path" || log_fatal "Failed to create directory for NFS export: $path"

    # Set ownership to nobody:nogroup, a common practice for NFS shares to avoid permission issues.
    chown nobody:nogroup "$path" || log_warn "Failed to set ownership on $path"
    chmod 777 "$path" || log_warn "Failed to set permissions on $path"

    # Construct the export line with each client having its own options.
    local export_line="$path"
    for client in "${clients_array[@]}"; do
      export_line+=" $client($options_str)"
    done

    # Idempotency check: Add the NFS export entry only if it doesn't already exist.
    if grep -q "^$path " "$exports_file"; then
      log_warn "Export line for $path already exists in $exports_file, skipping addition"
    else
      echo "$export_line" >> "$exports_file" || log_fatal "Failed to add '$export_line' to $exports_file"
      log_info "Added NFS export: $export_line"
      configured_exports=$((configured_exports + 1))
    fi
  done

  if [[ "$configured_exports" -eq 0 ]]; then
    log_warn "No NFS exports configured based on hypervisor_config.json."
  fi

  # Refresh NFS exports and restart the service to apply changes.
  log_info "Refreshing and restarting NFS exports/services..."
  retry_command "exportfs -ra" || log_fatal "Failed to refresh NFS exports (exportfs -ra)"
  retry_command "systemctl restart nfs-server nfs-kernel-server 2>/dev/null || systemctl restart nfs-kernel-server" || log_fatal "Failed to restart NFS service"
  log_info "NFS exports configured and service restarted"
}

# =====================================================================================
# Function: configure_nfs_firewall
# Description: Configures the Uncomplicated Firewall (UFW) to allow NFS traffic from the
#              subnet defined in the configuration. This is essential for clients to be
#              able to connect to the NFS server.
# =====================================================================================
configure_nfs_firewall() {
  log_info "NFS firewall configuration is now managed by hypervisor_feature_setup_firewall.sh. Skipping."
}

# =====================================================================================
# Function: add_nfs_storage
# Description: Integrates the configured NFS shares as storage resources within Proxmox VE.
#              It verifies that the `pvesm` tool is available, checks that the NFS exports
#              are active, and then uses `pvesm add nfs` to make the shares available for
#              storing VM images, ISOs, backups, etc.
# =====================================================================================
add_nfs_storage() {
  log_info "Adding NFS storage to Proxmox..."
  
  # Inner function to check for the pvesm command.
  check_pvesm() {
    if ! command -v pvesm >/dev/null 2>&1; then
      log_fatal "pvesm command not found. This script must be run on a Proxmox VE host."
    fi
    log_info "Verified pvesm availability."
  }

  check_pvesm

  local server_ip
  server_ip=$(get_server_ip)
  local nfs_shares_config
  nfs_shares_config=$(jq -c '.nfs.exports[]' "$HYPERVISOR_CONFIG_FILE")
  local added_proxmox_storage=0

  for share_json in $nfs_shares_config; do
    local path=$(echo "$share_json" | jq -r '.path')
    # Define the types of content this storage can hold within Proxmox.
    local content_type="images,iso,vztmpl,backup,snippets"
    # Derive a unique storage name from the path for use in Proxmox.
    local storage_name="nfs-$(basename "$path" | tr '/' '-')"

    # Idempotency check: Skip if a Proxmox storage entry with this name already exists.
    if pvesm status | grep -q "^$storage_name "; then
      log_info "Proxmox storage $storage_name already exists, skipping addition."
      continue
    fi

    log_info "Checking if export $path is available on $server_ip..."
    # Verify that the NFS export is actually available on the network before trying to add it.
    if ! showmount -e "$server_ip" | grep -q "$(echo "$path" | sed 's/\//\\\//g')"; then
      log_fatal "NFS export $path not available on $server_ip according to showmount. Check NFS server configuration."
    fi
    log_info "Confirmed export $path is available on $server_ip"

    # Define and create the local mount point that Proxmox will use for this storage.
    local local_mount="/mnt/nfs/$storage_name"
    mkdir -p "$local_mount" || log_fatal "Failed to create local mount point $local_mount for Proxmox NFS storage"
    
    log_info "Adding NFS storage $storage_name to Proxmox..."
    # Add the NFS share as a storage resource in Proxmox.
    retry_command "pvesm add nfs $storage_name --server $server_ip --export $path --content $content_type --path $local_mount --options vers=4,soft,timeo=30,retrans=3" || log_fatal "Failed to add NFS storage $storage_name using pvesm"
    log_info "Successfully added NFS storage $storage_name for $path at $local_mount with content $content_type"
    added_proxmox_storage=$((added_proxmox_storage + 1))
  done

  if [[ "$added_proxmox_storage" -eq 0 ]]; then
    log_warn "No NFS storage added to Proxmox based on hypervisor_config.json."
  fi
}

# =====================================================================================
# Function: main
# Description: Main execution flow for the NFS setup script. It orchestrates all the
#              necessary steps to set up a fully functional and integrated NFS server.
# =====================================================================================
main() {
  install_nfs_packages
  configure_nfs_locking
  configure_nfs_exports
  configure_nfs_firewall
  add_nfs_storage

  log_info "A reboot is recommended to apply NFS changes. Please reboot manually."
  
  log_info "Successfully completed hypervisor_feature_setup_nfs.sh"
  exit 0
}

main "$@"