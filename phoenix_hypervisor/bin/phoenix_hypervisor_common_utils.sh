#!/bin/bash
#
# File: phoenix_hypervisor_common_utils.sh
# Description: Centralized environment and logging functions for all Phoenix Hypervisor scripts.
#              This script should be sourced by all other scripts to ensure a consistent
#              execution environment and standardized logging.
# Version: 1.0.0
# Author: Roo (AI Architect)

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Global Constants ---
export HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"
export LXC_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
export LXC_CONFIG_SCHEMA_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json"
export MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"

# --- Environment Setup ---
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export PATH="/usr/local/bin:$PATH" # Ensure /usr/local/bin is in PATH for globally installed npm packages like ajv-cli

# --- Logging Functions ---
log_debug() {
    if [ "$PHOENIX_DEBUG" == "true" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $(basename "$0"): $*" | tee -a "$MAIN_LOG_FILE"
    fi
}

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $(basename "$0"): $*" | tee -a "$MAIN_LOG_FILE"
}

log_warn() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $(basename "$0"): $*" | tee -a "$MAIN_LOG_FILE" >&2
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $(basename "$0"): $*" | tee -a "$MAIN_LOG_FILE" >&2
}

log_fatal() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [FATAL] $(basename "$0"): $*" | tee -a "$MAIN_LOG_FILE" >&2
    exit 1
}

# =====================================================================================
# Function: log_plain_output
# Description: Logs multi-line output from a variable or command, preserving formatting.
#              Designed to be used with pipes.
# =====================================================================================
log_plain_output() {
    # This function is designed to be used with pipes for multi-line output.
    # Example: echo "Line 1\nLine 2" | log_plain_output
    while IFS= read -r line; do
        echo "    | $line" | tee -a "$MAIN_LOG_FILE"
    done
}
 
 # --- Exit Function ---
 exit_script() {
    local exit_code=$1
    if [ "$exit_code" -eq 0 ]; then
        log_info "Script completed successfully."
    else
        log_error "Script failed with exit code $exit_code."
    fi
    exit "$exit_code"
}

# =====================================================================================
# Function: pct_exec
# Description: Executes a command inside an LXC container using 'pct exec'.
#              Handles errors and ensures commands are run with appropriate privileges.
# Arguments:
#   $1 (ctid) - The container ID.
#   $@ - The command and its arguments to execute inside the container.
# =====================================================================================
pct_exec() {
    local ctid="$1"
    shift # Remove ctid from the arguments list
    local cmd_args=("$@")

    log_info "Executing in CTID $ctid: ${cmd_args[*]}"
    if ! pct exec "$ctid" -- "${cmd_args[@]}"; then
        log_error "Command failed in CTID $ctid: '${cmd_args[*]}'"
        return 1
    fi
    return 0
}

# =====================================================================================
# Function: jq_get_value
# Description: A robust wrapper for jq to query the LXC config file.
#              It retrieves a specific value from the JSON configuration for a given CTID.
# Arguments:
#   $1 (ctid) - The container ID.
#   $2 (jq_query) - The jq query string to execute.
# Returns:
#   The queried value on success, and a non-zero status code on failure.
# =====================================================================================
jq_get_value() {
    local ctid="$1"
    local jq_query="$2"
    local value

    value=$(jq -r --arg ctid "$ctid" ".lxc_configs[\$ctid | tostring] | ${jq_query}" "$LXC_CONFIG_FILE")

    if [ "$?" -ne 0 ]; then
        log_error "jq command failed for CTID $ctid with query '${jq_query}'."
        return 1
    elif [ -z "$value" ] || [ "$value" == "null" ]; then
        # This is not always an error, some fields are optional.
        # The calling function should handle empty values if they are not expected.
        return 1
    fi

    echo "$value"
    return 0
}

# =====================================================================================
# Function: run_pct_command
# Description: A robust wrapper for executing pct commands with error handling.
#              In dry-run mode, it logs the command instead of executing it.
# Arguments:
#   $@ - The arguments to pass to the 'pct' command.
# Returns:
#   0 on success, 1 on failure.
# =====================================================================================
run_pct_command() {
    local pct_args=("$@")
    log_info "Executing: pct ${pct_args[*]}"

    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN: Would execute 'pct ${pct_args[*]}'"
        return 0
    fi

    if ! pct "${pct_args[@]}"; then
        log_error "'pct ${pct_args[*]}' command failed."
        return 1
    fi
    log_info "'pct ${pct_args[*]}' command executed successfully."
    return 0
}

# =====================================================================================
# Function: ensure_nvidia_repo_is_configured
# Description: Ensures the NVIDIA CUDA repository is configured in the container.
#              This function is idempotent and can be called safely multiple times.
# Arguments:
#   $1 (ctid) - The container ID.
# =====================================================================================
ensure_nvidia_repo_is_configured() {
    local ctid="$1"
    log_info "Ensuring NVIDIA CUDA repository is configured in CTID $ctid..."

    if pct_exec "$ctid" [ -f /etc/apt/sources.list.d/cuda.list ]; then
        log_info "NVIDIA CUDA repository already configured. Skipping."
        return 0
    fi

    local nvidia_repo_url=$(jq -r '.nvidia_repo_url' "$LXC_CONFIG_FILE")
    local cuda_pin_url="${nvidia_repo_url}cuda-ubuntu2404.pin"
    local cuda_key_url="${nvidia_repo_url}3bf863cc.pub"
    local cuda_keyring_path="/etc/apt/trusted.gpg.d/cuda-archive-keyring.gpg"

    pct_exec "$ctid" wget -qO /etc/apt/preferences.d/cuda-repository-pin-600 "$cuda_pin_url"
    pct_exec "$ctid" curl -fsSL "$cuda_key_url" | pct_exec "$ctid" gpg --dearmor -o "$cuda_keyring_path"
    pct_exec "$ctid" bash -c "echo \"deb [signed-by=${cuda_keyring_path}] ${nvidia_repo_url} /\" > /etc/apt/sources.list.d/cuda.list"
    pct_exec "$ctid" apt-get update
}

# --- Initial Environment Check (only run once per main script execution) ---
# This block ensures that the environment is initialized only when the script is run directly,
# not when sourced by other scripts.
if [[ "${BASH_SOURCE}" == "${0}" ]]; then
    # Initialize/Clear the main log file only if this is the main script execution
    > "$MAIN_LOG_FILE"
    log_info "Environment script initialized."
fi

# --- Common Utility Functions from phoenix-scripts/common.sh ---

# check_root: Ensures script runs as root
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "common-1.2", "keywords": ["root", "auth"], "comment_type": "block"}
check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_fatal "This script must be run as root"
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
    log_fatal "No host provided for connectivity check."
  fi

  until ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; do
    if ((attempt < max_attempts)); then
      log_warn "Failed to reach $host, retrying ($((attempt + 1))/$max_attempts)"
      ((attempt++))
      sleep 5
    else
      log_fatal "Cannot reach $host after $max_attempts attempts. Check network configuration."
    fi
  done
  log_info "Network connectivity to $host verified"
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
      log_warn "Failed to reach $dns_server, retrying ($((attempt + 1))/$max_attempts)"
      ((attempt++))
      sleep 5
    else
      log_warn "No internet connectivity to $dns_server after $max_attempts attempts. Some operations may fail."
      return 1
    fi
  done
  log_info "Internet connectivity to $dns_server verified"
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
    log_fatal "Invalid subnet format: $subnet"
  fi

  local subnet_prefix=$(echo "$subnet" | cut -d'/' -f1 | sed 's/\.[0-9]*$/\./')
  while IFS= read -r line; do
    if [[ "$line" =~ inet\ (10\.0\.0\.[0-9]+/[0-9]+) ]]; then
      ip_with_mask="${BASH_REMATCH}"
      ip=$(echo "$ip_with_mask" | cut -d'/' -f1)
      if [[ "$ip" =~ ^$subnet_prefix ]]; then
        found=1
        log_info "Found network interface with IP $ip_with_mask in subnet $subnet"
        break
      fi
    fi
  done < <(ip addr show | grep inet)

  if [[ $found -eq 0 ]]; then
    log_warn "No network interface found in subnet $subnet. NFS may not function correctly."
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
    log_fatal "Failed to create ZFS dataset $pool/$dataset with mountpoint $mountpoint"
  }
  if ! zfs list -H -o name | grep -q "^$pool/$dataset$"; then
    log_fatal "Failed to verify ZFS dataset creation for $pool/$dataset"
  fi
  log_info "Successfully created ZFS dataset: $pool/$dataset with mountpoint $mountpoint"
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
      log_fatal "Failed to set property $prop on $dataset"
    }
    log_info "Set property $prop on $dataset"
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
    log_fatal "Failed to add NFS export for $mountpoint"
  }
  exportfs -ra || {
    log_fatal "Failed to refresh NFS exports"
  }
  log_info "Configured NFS export for $dataset at $mountpoint"
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
      log_warn "Command failed, retrying ($((attempt + 1))/${max_attempts}): $cmd"
      ((attempt++))
      sleep 5
    else
      log_error "Command failed after ${max_attempts} attempts: $cmd"
      return 1
    fi
  done
  log_info "Command succeeded: $cmd"
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
      log_fatal "Failed to add user $username to group $group"
    }
  fi
  log_info "Added user $username to group $group"
}

# verify_nfs_exports: Verifies NFS export configuration
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "common-1.12", "keywords": ["nfs", "export"], "comment_type": "block"}
verify_nfs_exports() {
  if ! exportfs -v >/dev/null 2>&1; then
    log_fatal "Failed to verify NFS exports"
  fi
  log_info "NFS exports verified"
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