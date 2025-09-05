# Metadata: {"chunk_id": "common-1.0", "keywords": ["utility", "proxmox", "zfs", "nfs"], "comment_type": "block"}
#!/bin/bash
# common.sh
# Shared functions for Proxmox VE setup scripts
# Version: 1.2.8
# Author: Heads, Grok, Devstral
# Usage: Source this script in other setup scripts to use common functions
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Constants
LOGFILE="/var/log/proxmox_setup.log"
LOGDIR=$(dirname "$LOGFILE")

# setup_logging: Creates log directory and file with appropriate permissions
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "common-1.1", "keywords": ["logging", "proxmox"], "comment_type": "block"}
# TODO: Validate LOGDIR permissions before creation
setup_logging() {
  mkdir -p "$LOGDIR" || { echo "Error: Failed to create log directory $LOGDIR" | tee -a /dev/stderr; exit 1; }
  touch "$LOGFILE" || { echo "Error: Failed to create log file $LOGFILE" | tee -a /dev/stderr; exit 1; }
  chmod 664 "$LOGFILE" || { echo "Error: Failed to set permissions on $LOGFILE" | tee -a /dev/stderr; exit 1; }
}

# check_root: Ensures script runs as root
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "common-1.2", "keywords": ["root", "auth"], "comment_type": "block"}
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" | tee -a "$LOGFILE"
    exit 1
  fi
}

# check_package: Verifies if a package is installed
# Args: package (string)
# Returns: 0 if installed, 1 if not
# Metadata: {"chunk_id": "common-1.3", "keywords": ["package", "dpkg"], "comment_type": "block"}
check_package() {
  local package="$1"
  dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"
}

# Algorithm: Network connectivity check
# Pings host with retries to verify reachability
# Keywords: [network, ping]
# check_network_connectivity: Verifies network connectivity to a host
# Args: host (string)
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "common-1.4", "keywords": ["network", "connectivity"], "comment_type": "block"}
# TODO: Add support for alternative connectivity checks (e.g., curl)
check_network_connectivity() {
  local host="$1"
  local max_attempts=3
  local attempt=0
  local timeout=5

  if [[ -z "$host" ]]; then
    echo "Error: No host provided for connectivity check." | tee -a "$LOGFILE"
    exit 1
  fi

  until ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; do
    if ((attempt < max_attempts)); then
      echo "[$(date)] Failed to reach $host, retrying ($((attempt + 1))/$max_attempts)" >> "$LOGFILE"
      ((attempt++))
      sleep 5
    else
      echo "Error: Cannot reach $host after $max_attempts attempts. Check network configuration." | tee -a "$LOGFILE"
      exit 1
    fi
  done
  echo "[$(date)] Network connectivity to $host verified" >> "$LOGFILE"
}

# Algorithm: Internet connectivity check
# Pings DNS server with retries to verify internet access
# Keywords: [internet, ping]
# check_internet_connectivity: Verifies internet connectivity via DNS server
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "common-1.5", "keywords": ["internet", "connectivity"], "comment_type": "block"}
# TODO: Add fallback DNS servers
check_internet_connectivity() {
  local dns_server="8.8.8.8"
  local max_attempts=3
  local attempt=0
  local timeout=5

  until ping -c 1 -W "$timeout" "$dns_server" >/dev/null 2>&1; do
    if ((attempt < max_attempts)); then
      echo "[$(date)] Failed to reach $dns_server, retrying ($((attempt + 1))/$max_attempts)" >> "$LOGFILE"
      ((attempt++))
      sleep 5
    else
      echo "Warning: No internet connectivity to $dns_server after $max_attempts attempts. Some operations may fail." | tee -a "$LOGFILE"
      return 1
    fi
  done
  echo "[$(date)] Internet connectivity to $dns_server verified" >> "$LOGFILE"
}

# check_interface_in_subnet: Verifies if an interface exists in a subnet
# Args: subnet (string)
# Returns: 0 if found, 1 if not
# Metadata: {"chunk_id": "common-1.6", "keywords": ["network", "subnet"], "comment_type": "block"}
# TODO: Add validation for IPv6 subnets
check_interface_in_subnet() {
  local subnet="$1"
  local found=0

  if ! [[ "$subnet" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    echo "Error: Invalid subnet format: $subnet" | tee -a "$LOGFILE"
    exit 1
  fi

  local subnet_prefix=$(echo "$subnet" | cut -d'/' -f1 | sed 's/\.[0-9]*$/\./')
  while IFS= read -r line; do
    if [[ "$line" =~ inet\ (10\.0\.0\.[0-9]+/[0-9]+) ]]; then
      ip_with_mask="${BASH_REMATCH[1]}"
      ip=$(echo "$ip_with_mask" | cut -d'/' -f1)
      if [[ "$ip" =~ ^$subnet_prefix ]]; then
        found=1
        echo "[$(date)] Found network interface with IP $ip_with_mask in subnet $subnet" >> "$LOGFILE"
        break
      fi
    fi
  done < <(ip addr show | grep inet)

  if [[ $found -eq 0 ]]; then
    echo "Warning: No network interface found in subnet $subnet. NFS may not function correctly." | tee -a "$LOGFILE"
    return 1
  fi
  return 0
}

# create_zfs_dataset: Creates a ZFS dataset with specified mountpoint
# Args: pool (string), dataset (string), mountpoint (string), additional properties (optional)
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "common-1.7", "keywords": ["zfs", "dataset"], "comment_type": "block"}
create_zfs_dataset() {
  local pool="$1"
  local dataset="$2"
  local mountpoint="$3"
  shift 3
  zfs create -o mountpoint="$mountpoint" "$@" "$pool/$dataset" || {
    echo "Error: Failed to create ZFS dataset $pool/$dataset with mountpoint $mountpoint" | tee -a "$LOGFILE"
    exit 1
  }
  if ! zfs list -H -o name | grep -q "^$pool/$dataset$"; then
    echo "Error: Failed to verify ZFS dataset creation for $pool/$dataset" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date)] Successfully created ZFS dataset: $pool/$dataset with mountpoint $mountpoint" >> "$LOGFILE"
}

# set_zfs_properties: Sets properties on a ZFS dataset
# Args: dataset (string), properties (array)
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "common-1.8", "keywords": ["zfs", "properties"], "comment_type": "block"}
set_zfs_properties() {
  local dataset="$1"
  shift
  local properties=("$@")

  for prop in "${properties[@]}"; do
    zfs set "$prop" "$dataset" || {
      echo "Error: Failed to set property $prop on $dataset" | tee -a "$LOGFILE"
      exit 1
    }
    echo "[$(date)] Set property $prop on $dataset" >> "$LOGFILE"
  done
}

# configure_nfs_export: Configures an NFS export for a dataset
# Args: dataset (string), mountpoint (string), subnet (string), options (string)
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "common-1.9", "keywords": ["nfs", "export"], "comment_type": "block"}
configure_nfs_export() {
  local dataset="$1"
  local mountpoint="$2"
  local subnet="$3"
  local options="$4"

  echo "$mountpoint $subnet($options)" >> /etc/exports || {
    echo "Error: Failed to add NFS export for $mountpoint" | tee -a "$LOGFILE"
    exit 1
  }
  exportfs -ra || {
    echo "Error: Failed to refresh NFS exports" | tee -a "$LOGFILE"
    exit 1
  }
  echo "[$(date)] Configured NFS export for $dataset at $mountpoint" >> "$LOGFILE"
}

# Algorithm: Command retry
# Executes command with retries on failure
# Keywords: [retry, error_handling]
# retry_command: Retries a command up to max attempts
# Args: cmd (string)
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "common-1.10", "keywords": ["retry", "error_handling"], "comment_type": "block"}
# TODO: Add input validation for cmd
retry_command() {
  local cmd="$1"
  local max_attempts=3
  local attempt=0

  until bash -c "$cmd"; do
    if ((attempt < max_attempts)); then
      echo "[$(date)] Command failed, retrying ($((attempt + 1))/${max_attempts}): $cmd" >> "$LOGFILE"
      ((attempt++))
      sleep 5
    else
      echo "Error: Command failed after ${max_attempts} attempts: $cmd" | tee -a "$LOGFILE"
      return 1
    fi
  done
  echo "[$(date)] Command succeeded: $cmd" >> "$LOGFILE"
  return 0
}

# add_user_to_group: Adds a user to a group
# Args: username (string), group (string)
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "common-1.11", "keywords": ["user", "group"], "comment_type": "block"}
add_user_to_group() {
  local username="$1"
  local group="$2"

  if ! id -nG "$username" | grep -qw "$group"; then
    usermod -aG "$group" "$username" || {
      echo "Error: Failed to add user $username to group $group" | tee -a "$LOGFILE"
      exit 1
    }
  fi
  echo "[$(date)] Added user $username to group $group" >> "$LOGFILE"
}

# verify_nfs_exports: Verifies NFS export configuration
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "common-1.12", "keywords": ["nfs", "export"], "comment_type": "block"}
verify_nfs_exports() {
  if ! exportfs -v >/dev/null 2>&1; then
    echo "Error: Failed to verify NFS exports" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date)] NFS exports verified" >> "$LOGFILE"
}

# zfs_pool_exists: Checks if a ZFS pool exists
# Args: pool (string)
# Returns: 0 if exists, 1 if not
# Metadata: {"chunk_id": "common-1.13", "keywords": ["zfs", "pool"], "comment_type": "block"}
zfs_pool_exists() {
  local pool="$1"
  if zpool list -H -o name | grep -q "^$pool$"; then
    return 0
  fi
  return 1
}

# zfs_dataset_exists: Checks if a ZFS dataset exists
# Args: dataset (string)
# Returns: 0 if exists, 1 if not
# Metadata: {"chunk_id": "common-1.14", "keywords": ["zfs", "dataset"], "comment_type": "block"}
zfs_dataset_exists() {
  local dataset="$1"
  if zfs list -H -o name | grep -q "^$dataset$"; then
    return 0
  fi
  return 1
}

# Note: setup_logging is defined but not automatically called.
# The sourcing script should call setup_logging after defining LOGFILE if needed before sourcing common.sh,
# or ensure common.sh's LOGFILE is acceptable.