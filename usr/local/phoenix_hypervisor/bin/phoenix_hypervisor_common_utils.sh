#!/bin/bash
#
# File: phoenix_hypervisor_common_utils.sh
# Description: Provids centralized environment setup, logging utilities, and common functions
#              for all Phoenix Hypervisor shell scripts. This script is designed to be sourced
#              by other scripts to ensure a consistent execution environment and standardized
#              logging practices across the hypervisor management system.
#              It includes context-aware logic to dynamically set the LXC_CONFIG_FILE path
#              based on whether it is running on the host or inside a container's temporary directory.
# Dependencies: jq, pct, dpkg-query, ping, ip, zfs, zpool, usermod, exportfs, wget, curl, gpg, apt-get
# Inputs: PHOENIX_DEBUG (environment variable for debug logging), DRY_RUN (environment variable for dry-run mode),
#         Various function arguments (e.g., CTID, package names, hostnames, subnets, ZFS pool/dataset names,
#         mount points, usernames, groups, commands, properties, options).
# Outputs: Log messages to stdout and MAIN_LOG_FILE, queried values from JSON (jq_get_value),
#          exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Global Constants ---
export HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"
export LXC_CONFIG_SCHEMA_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json"
export MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"

# --- Dynamic LXC_CONFIG_FILE Path ---
# Determine the directory of the currently executing script.
SCRIPT_DIR_FOR_CONFIG=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

if [[ "$SCRIPT_DIR_FOR_CONFIG" == "/tmp/phoenix_run" ]]; then
    # We are running inside the container's temporary execution environment.
    export LXC_CONFIG_FILE="${SCRIPT_DIR_FOR_CONFIG}/phoenix_lxc_configs.json"
else
    # We are running on the host. Use the standard absolute path.
    export LXC_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
fi

# --- Environment Setup ---
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export PATH="/usr/local/bin:$PATH" # Ensure /usr/local/bin is in PATH for globally installed npm packages like ajv-cli

# --- Color Codes ---
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# --- Logging Functions ---
# =====================================================================================
# Function: log_debug
# Description: Logs a debug message to stdout and the main log file if PHOENIX_DEBUG is true.
# Arguments:
#   $@ - The message to log.
# Returns:
#   None.
# =====================================================================================
log_debug() {
    # Check if debug mode is enabled
    if [ "$PHOENIX_DEBUG" == "true" ]; then
        # Log the debug message with timestamp and script name
        echo -e "${COLOR_BLUE}$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $(basename "$0"): $*${COLOR_RESET}" | tee -a "$MAIN_LOG_FILE" >&2
    fi
}

# =====================================================================================
# Function: log_info
# Description: Logs an informational message to stdout and the main log file.
# Arguments:
#   $@ - The message to log.
# Returns:
#   None.
# =====================================================================================
log_info() {
    # Log the informational message with timestamp and script name
    echo -e "${COLOR_GREEN}$(date '+%Y-%m-%d %H:%M:%S') [INFO] $(basename "$0"): $*${COLOR_RESET}" | tee -a "$MAIN_LOG_FILE" >&2
}

# =====================================================================================
# Function: log_success
# Description: Logs a success message to stdout and the main log file.
# Arguments:
#   $@ - The message to log.
# Returns:
#   None.
# =====================================================================================
log_success() {
    # Log the success message with timestamp and script name
    echo -e "${COLOR_GREEN}$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $(basename "$0"): $*${COLOR_RESET}" | tee -a "$MAIN_LOG_FILE" >&2
}

# =====================================================================================
# Function: log_warn
# Description: Logs a warning message to stderr and the main log file.
# Arguments:
#   $@ - The message to log.
# Returns:
#   None.
# =====================================================================================
log_warn() {
	# Log the warning message with timestamp and script name to stderr
	echo -e "${COLOR_YELLOW}$(date '+%Y-%m-%d %H:%M:%S') [WARN] $(basename "$0"): $*${COLOR_RESET}" | tee -a "$MAIN_LOG_FILE" >&2
}

# =====================================================================================
# Function: log_error
# Description: Logs an error message to stderr and the main log file.
# Arguments:
#   $@ - The message to log.
# Returns:
#   None.
# =====================================================================================
log_error() {
    # Log the error message with timestamp and script name to stderr
    echo -e "${COLOR_RED}$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $(basename "$0"): $*${COLOR_RESET}" | tee -a "$MAIN_LOG_FILE" >&2
}

# =====================================================================================
# Function: log_fatal
# Description: Logs a fatal error message to stderr and the main log file, then exits the script with status 1.
# Arguments:
#   $@ - The message to log.
# Returns:
#   Exits the script with status 1.
# =====================================================================================
log_fatal() {
    # Log the fatal message with timestamp and script name to stderr
    echo "$(date '+%Y-%m-%d %H:%M:%S') [FATAL] $(basename "$0"): $*" | tee -a "$MAIN_LOG_FILE" >&2
    # Exit the script due to a fatal error
    exit 1
}

# =====================================================================================
# Function: setup_logging
# Description: Ensures the log directory exists and the log file is available.
# Arguments:
#   $1 - The full path to the log file.
# =====================================================================================
setup_logging() {
    local log_file="$1"
    local log_dir
    log_dir=$(dirname "$log_file")

    if [ ! -d "$log_dir" ]; then
        # Create the log directory if it doesn't exist
        mkdir -p "$log_dir" || log_fatal "Failed to create log directory: $log_dir"
    fi
    # Touch the log file to ensure it exists
    touch "$log_file" || log_fatal "Failed to create log file: $log_file"
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
#              NOTE: This function is robust and automatically handles the '--' separator.
#              It is safe to call with or without it.
# Arguments:
#   $1 (ctid) - The container ID.
#   $@ - The command and its arguments to execute inside the container.
# =====================================================================================
pct_exec() {
    local ctid="$1"
    shift # Remove ctid from the arguments list

    # If the first argument is '--', remove it to make the function more robust.
    if [[ "$1" == "--" ]]; then
        shift
    fi

    local cmd_args=("$@")

    # Context-aware execution: check if running inside the container's temp dir
    if [[ "$SCRIPT_DIR_FOR_CONFIG" == "/tmp/phoenix_run" ]]; then
        log_info "Executing command inside container: ${cmd_args[*]}"
        # When inside the container, execute the command directly using bash -c
        # This is necessary because 'pct' is a host-only command.
        if ! "${cmd_args[@]}"; then
            log_error "Command failed inside container: '${cmd_args[@]}'"
            return 1
        fi
    else
        # When on the host, use 'pct exec' to run the command inside the container
        log_info "Executing command from host in CTID $ctid: ${cmd_args[@]}"
        local output
        output=$(pct exec "$ctid" -- "${cmd_args[@]}" 2>&1)
        if [ $? -ne 0 ]; then
            log_error "Command failed in CTID $ctid: '${cmd_args[@]}'"
            log_error "Output:\n$output"
            return 1
        fi
        echo "$output"
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

    # Log the exact query for debugging purposes
    log_debug "Executing jq query for CTID $ctid: .lxc_configs[\$ctid | tostring] | ${jq_query}"

    # Execute jq to query the LXC config file for the specified CTID and query
    value=$(jq -r --arg ctid "$ctid" ".lxc_configs[\$ctid | tostring] | ${jq_query}" "$LXC_CONFIG_FILE")

    # If the value is not found in the container's config, check the root of the file.
    if [ -z "$value" ] || [ "$value" == "null" ]; then
        log_debug "Value not found in CTID $ctid config. Checking root of the file for query: ${jq_query}"
        value=$(jq -r "${jq_query}" "$LXC_CONFIG_FILE")
    fi

    # Check if jq command failed
    if [ "$?" -ne 0 ]; then
        log_error "jq command failed for CTID $ctid with query '${jq_query}'."
        return 1
    # Check if the value is empty or "null"
    elif [ -z "$value" ] || [ "$value" == "null" ]; then
        # Note: This is not always an error, as some fields are optional.
        # The calling function is responsible for handling empty values if they are not expected.
        return 1
    fi

    echo "$value"
    return 0
}

# =====================================================================================
# Function: jq_get_array
# Description: A robust wrapper for jq to query the LXC config file for an array.
#              It retrieves all elements of a JSON array for a given CTID.
# Arguments:
#   $1 (ctid) - The container ID.
#   $2 (jq_query) - The jq query string that selects the array.
# Returns:
#   The elements of the array, each on a new line.
# =====================================================================================
jq_get_array() {
    local ctid="$1"
    local jq_query="$2"
    local values

    values=$(jq -r --arg ctid "$ctid" ".lxc_configs[\$ctid | tostring] | ${jq_query}" "$LXC_CONFIG_FILE")

    if [ "$?" -ne 0 ]; then
        log_error "jq command failed for CTID $ctid with query '${jq_query}'."
        return 1
    elif [ -z "$values" ] || [ "$values" == "null" ]; then
        return 1
    fi

    echo "$values"
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

    # If DRY_RUN mode is enabled, log the command without executing it
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN: Would execute 'pct ${pct_args[*]}'"
        return 0
    fi

    # Execute the pct command
    local output
    local exit_code=0
    # Capture the output and exit code of the pct command.
    output=$(pct "${pct_args[@]}" 2>&1) || exit_code=$?

    # Log the captured output and exit code for debugging purposes.
    log_debug "pct command output:\n$output"
    log_debug "pct command exit code: $exit_code"

    # Check if the command failed (exit code is not 0).
    if [ $exit_code -ne 0 ]; then
        # Check for the specific non-error condition of the disk already being the correct size.
        if [[ "${pct_args[0]}" == "resize" && "$output" == *"disk is already at specified size"* ]]; then
            log_info "Ignoring non-fatal error for 'pct resize': $output"
        else
            # For all other errors, log the failure and return an error code.
            log_error "'pct ${pct_args[*]}' command failed with exit code $exit_code."
            log_error "Output:\n$output"
            return 1
        fi
    fi
    log_info "'pct ${pct_args[*]}' command executed successfully."
    return 0
}
# =====================================================================================
# Function: run_pct_push
# Description: A robust wrapper for 'pct push' with retries and verification.
#              This function pushes a file to a container, creating the destination
#              directory if it doesn't exist, and verifies the transfer.
# Arguments:
#   $1 (ctid) - The container ID.
#   $2 (host_path) - The path of the file on the host.
#   $3 (container_path) - The destination path in the container.
#   $4 (max_attempts) - Optional: Maximum number of push attempts (default: 3).
#   $5 (delay) - Optional: Delay in seconds between retries (default: 5).
# Returns:
#   0 on success, 1 on failure after all retries.
# =====================================================================================
run_pct_push() {
    local ctid="$1"
    local host_path="$2"
    local container_path="$3"
    local max_attempts="${4:-3}"
    local delay="${5:-5}"
    local attempt=1

    # Ensure the destination directory exists in the container
    local container_dir
    container_dir=$(dirname "$container_path")
    log_info "Ensuring destination directory '$container_dir' exists in CTID $ctid..."
    if ! pct_exec "$ctid" mkdir -p "$container_dir"; then
        log_fatal "Failed to create directory '$container_dir' in CTID $ctid. Aborting file push."
        return 1
    fi

    while [ $attempt -le $max_attempts ]; do
        log_info "Attempt $attempt/$max_attempts: Pushing '$host_path' to CTID $ctid at '$container_path'..."
        
        local output
        local exit_code=0
        output=$(pct push "$ctid" "$host_path" "$container_path" 2>&1) || exit_code=$?

        if [ $exit_code -eq 0 ]; then
            log_info "File push command succeeded. Verifying file existence in container..."
            if pct_exec "$ctid" test -f "$container_path"; then
                log_success "File successfully pushed and verified in CTID $ctid."
                return 0
            else
                log_warn "File push command succeeded, but verification failed. File not found at '$container_path'."
            fi
        else
            log_error "File push command failed with exit code $exit_code."
            log_error "Output:\n$output"
        fi

        if [ $attempt -lt $max_attempts ]; then
            log_info "Waiting for $delay seconds before retrying..."
            sleep "$delay"
        fi
        ((attempt++))
    done

    log_fatal "Failed to push file to CTID $ctid after $max_attempts attempts."
    return 1
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

    # Check if the NVIDIA CUDA repository is already configured
    # Check if the NVIDIA CUDA repository is already configured.
    # The command will return a non-zero exit code if the file does not exist, which is the expected behavior.
    # We directly use 'pct exec' here to avoid the error logging from our 'pct_exec' wrapper,
    # as a non-zero exit code is expected if the file doesn't exist.
    if pct exec "$ctid" -- test -f /etc/apt/sources.list.d/cuda.list >/dev/null 2>&1; then
        log_info "NVIDIA CUDA repository already configured. Skipping."
        return 0
    else
        log_info "NVIDIA CUDA repository not found. Proceeding with configuration."
    fi

    # Retrieve NVIDIA repository URL from LXC config file
    local nvidia_repo_url=$(jq -r '.nvidia_repo_url' "$LXC_CONFIG_FILE")
    local cuda_pin_url="${nvidia_repo_url}cuda-ubuntu2404.pin" # Construct CUDA pin URL
    local cuda_key_url="${nvidia_repo_url}3bf863cc.pub" # Construct CUDA key URL
    local cuda_keyring_path="/etc/apt/trusted.gpg.d/cuda-archive-keyring.gpg" # Define keyring path

    # Download and install CUDA repository pin
    pct_exec "$ctid" wget -qO /etc/apt/preferences.d/cuda-repository-pin-600 "$cuda_pin_url"
    # Download and install CUDA public key
    pct_exec "$ctid" bash -c "curl -fsSL \"$cuda_key_url\" | gpg --dearmor -o \"$cuda_keyring_path\""
    # Add CUDA repository to sources list
    pct_exec "$ctid" bash -c "echo 'deb [signed-by=${cuda_keyring_path}] ${nvidia_repo_url} /' > /etc/apt/sources.list.d/cuda.list"
    # Update apt package list
    pct_exec "$ctid" apt-get update
}

# --- Initial Environment Check (only run once per main script execution) ---
# This block ensures that the environment is initialized only when the script is run directly,
# not when sourced by other scripts.
if [[ "${BASH_SOURCE}" == "${0}" ]]; then
    # Initialize/Clear the main log file only if this is the main script execution, not when sourced.
    > "$MAIN_LOG_FILE"
    log_info "Environment script initialized."
fi

# --- Common Utility Functions from phoenix-scripts/common.sh ---

# =====================================================================================
# Function: check_root
# Description: Ensures that the script is being run with root privileges.
# Arguments:
#   None.
# Returns:
#   Exits with a fatal error if the script is not run as root.
# =====================================================================================
check_root() {
  # Check if the effective user ID is not 0 (root)
  if [[ $EUID -ne 0 ]]; then
    log_fatal "This script must be run as root"
  fi
}

# =====================================================================================
# Function: check_package
# Description: Verifies if a specified Debian package is installed on the system.
# Arguments:
#   $1 (package) - The name of the package to check.
# Returns:
#   0 if the package is installed, 1 otherwise.
# =====================================================================================
check_package() {
  local package="$1" # Capture the package name
  # Query dpkg for the package status and check if it's "install ok installed"
  dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"
}

# Algorithm: Network connectivity check
# Pings host with retries to verify reachability
# Keywords: [network, ping]
# =====================================================================================
# Function: check_network_connectivity
# Description: Verifies network connectivity to a specified host by pinging it with retries.
# Arguments:
#   $1 (host) - The hostname or IP address to ping.
# Returns:
#   0 on successful connectivity, exits with a fatal error on failure after retries.
# =====================================================================================
check_network_connectivity() {
  local host="$1" # Host to check connectivity against
  local max_attempts=3 # Maximum number of ping attempts
  local attempt=0 # Current attempt counter
  local timeout=5 # Ping timeout in seconds

  # Validate that a host was provided
  if [[ -z "$host" ]]; then
    log_fatal "No host provided for connectivity check."
  fi

  # Loop until ping is successful or max attempts are reached
  until ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; do
    if ((attempt < max_attempts)); then
      log_warn "Failed to reach $host, retrying ($((attempt + 1))/$max_attempts)"
      ((attempt++)) # Increment attempt counter
      sleep 5 # Wait before retrying
    else
      log_fatal "Cannot reach $host after $max_attempts attempts. Check network configuration."
    fi
  done
  log_info "Network connectivity to $host verified"
}

# Algorithm: Internet connectivity check
# Pings DNS server with retries to verify internet access
# Keywords: [internet, ping]
# =====================================================================================
# Function: check_internet_connectivity
# Description: Verifies general internet connectivity by pinging a well-known DNS server (8.8.8.8) with retries.
# Arguments:
#   None.
# Returns:
#   0 on successful internet connectivity, 1 on failure after retries.
# =====================================================================================
check_internet_connectivity() {
  local dns_server="8.8.8.8" # Google's public DNS server
  local max_attempts=3 # Maximum number of ping attempts
  local attempt=0 # Current attempt counter
  local timeout=5 # Ping timeout in seconds

  # Loop until ping is successful or max attempts are reached
  until ping -c 1 -W "$timeout" "$dns_server" >/dev/null 2>&1; do
    if ((attempt < max_attempts)); then
      log_warn "Failed to reach $dns_server, retrying ($((attempt + 1))/$max_attempts)"
      ((attempt++)) # Increment attempt counter
      sleep 5 # Wait before retrying
    else
      log_warn "No internet connectivity to $dns_server after $max_attempts attempts. Some operations may fail."
      return 1
    fi
  done
  log_info "Internet connectivity to $dns_server verified"
}

# =====================================================================================
# Function: check_interface_in_subnet
# Description: Checks if any network interface on the system is configured within a given IPv4 subnet.
# Arguments:
#   $1 (subnet) - The IPv4 subnet in CIDR notation (e.g., "192.168.1.0/24").
# Returns:
#   0 if an interface is found in the subnet, 1 otherwise. Exits with a fatal error for invalid subnet format.
# =====================================================================================
check_interface_in_subnet() {
  local subnet="$1" # The subnet to check against
  local found=0 # Flag to indicate if an interface is found

  # Validate subnet format using regex
  if ! [[ "$subnet" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    log_fatal "Invalid subnet format: $subnet"
  fi

  # Extract the network prefix from the provided subnet
  local subnet_prefix=$(echo "$subnet" | cut -d'/' -f1 | sed 's/\.[0-9]*$/\./')
  # Iterate through network interfaces to find an IP in the specified subnet
  while IFS= read -r line; do
    # Use regex to find IPv4 addresses with their masks
    if [[ "$line" =~ inet\ (10\.0\.0\.[0-9]+/[0-9]+) ]]; then
      ip_with_mask="${BASH_REMATCH}" # Capture the matched IP with mask
      ip=$(echo "$ip_with_mask" | cut -d'/' -f1) # Extract just the IP address
      # Check if the IP address matches the subnet prefix
      if [[ "$ip" =~ ^$subnet_prefix ]]; then
        found=1 # Set flag to true
        log_info "Found network interface with IP $ip_with_mask in subnet $subnet"
        break # Exit loop once found
      fi
    fi
  done < <(ip addr show | grep inet) # Pipe output of 'ip addr show' to the while loop

  if [[ $found -eq 0 ]]; then
    log_warn "No network interface found in subnet $subnet. NFS may not function correctly."
    return 1
  fi
  return 0
}

# =====================================================================================
# Function: create_zfs_dataset
# Description: Creates a ZFS dataset with a specified mountpoint and optional additional properties.
# Arguments:
#   $1 (pool) - The name of the ZFS pool.
#   $2 (dataset) - The name of the dataset to create within the pool.
#   $3 (mountpoint) - The desired mountpoint for the new dataset.
#   $@ (additional properties) - Optional additional ZFS properties to set (e.g., "compression=lz4").
# Returns:
#   Exits with a fatal error if dataset creation or verification fails.
# =====================================================================================
create_zfs_dataset() {
  local pool="$1" # ZFS pool name
  local dataset="$2" # ZFS dataset name
  local mountpoint="$3" # Mountpoint for the dataset
  shift 3 # Shift arguments to get additional properties
  # Create the ZFS dataset with the specified mountpoint and any additional properties
  zfs create -o mountpoint="$mountpoint" "$@" "$pool/$dataset" || {
    log_fatal "Failed to create ZFS dataset $pool/$dataset with mountpoint $mountpoint"
  }
  # Verify that the ZFS dataset was created successfully
  if ! zfs list -H -o name | grep -q "^$pool/$dataset$"; then
    log_fatal "Failed to verify ZFS dataset creation for $pool/$dataset"
  fi
  log_info "Successfully created ZFS dataset: $pool/$dataset with mountpoint $mountpoint"
}

# =====================================================================================
# Function: set_zfs_properties
# Description: Sets one or more properties on a specified ZFS dataset.
# Arguments:
#   $1 (dataset) - The full name of the ZFS dataset (e.g., "pool/dataset").
#   $@ (properties) - A list of properties to set (e.g., "compression=lz4", "sharenfs=on").
# Returns:
#   Exits with a fatal error if any property fails to be set.
# =====================================================================================
set_zfs_properties() {
  local dataset="$1" # ZFS dataset name
  shift # Remove dataset from arguments
  local properties=("$@") # Remaining arguments are properties

  # Iterate through each property and set it on the dataset
  for prop in "${properties[@]}"; do
    zfs set "$prop" "$dataset" || {
      log_fatal "Failed to set property $prop on $dataset"
    }
    log_info "Set property $prop on $dataset"
  done
}

# =====================================================================================
# Function: configure_nfs_export
# Description: Configures an NFS export for a given dataset by adding an entry to /etc/exports
#              and refreshing the NFS export list.
# Arguments:
#   $1 (dataset) - The name of the ZFS dataset being exported (for logging purposes).
#   $2 (mountpoint) - The mountpoint of the dataset to be exported.
#   $3 (subnet) - The network subnet allowed to access the export (e.g., "192.168.1.0/24").
#   $4 (options) - NFS export options (e.g., "rw,sync,no_subtree_check").
# Returns:
#   Exits with a fatal error if adding the export or refreshing fails.
# =====================================================================================
configure_nfs_export() {
  local dataset="$1" # ZFS dataset name
  local mountpoint="$2" # Mountpoint to export
  local subnet="$3" # Subnet allowed to access
  local options="$4" # NFS export options

  # Add the NFS export entry to /etc/exports
  echo "$mountpoint $subnet($options)" >> /etc/exports || {
    log_fatal "Failed to add NFS export for $mountpoint"
  }
  # Refresh the NFS export list to apply changes
  exportfs -ra || {
    log_fatal "Failed to refresh NFS exports"
  }
  log_info "Configured NFS export for $dataset at $mountpoint"
}

# Algorithm: Command retry
# Executes command with retries on failure
# Keywords: [retry, error_handling]
# =====================================================================================
# Function: retry_command
# Description: Executes a given command, retrying it up to a maximum number of attempts
#              if it fails.
# Arguments:
#   $1 (cmd) - The command string to execute.
# Returns:
#   0 on successful command execution, 1 if the command fails after all retries.
# =====================================================================================
retry_command() {
  local cmd="$1" # Command to be retried
  local max_attempts=3 # Maximum number of attempts
  local attempt=0 # Current attempt counter

  # Loop until the command succeeds or max attempts are reached
  until bash -c "$cmd"; do
    if ((attempt < max_attempts)); then
      log_warn "Command failed, retrying ($((attempt + 1))/${max_attempts}): $cmd"
      ((attempt++)) # Increment attempt counter
      sleep 5 # Wait before retrying
    else
      log_error "Command failed after ${max_attempts} attempts: $cmd"
      return 1
    fi
  done
  log_info "Command succeeded: $cmd"
  return 0
}

# =====================================================================================
# Function: add_user_to_group
# Description: Adds a specified user to a specified group if the user is not already a member.
# Arguments:
#   $1 (username) - The username to add to the group.
#   $2 (group) - The name of the group.
# Returns:
#   Exits with a fatal error if adding the user to the group fails.
# =====================================================================================
add_user_to_group() {
  local username="$1" # Username to add
  local group="$2" # Group to add the user to

  # Check if the user is already a member of the group
  if ! id -nG "$username" | grep -qw "$group"; then
    # Add the user to the group
    usermod -aG "$group" "$username" || {
      log_fatal "Failed to add user $username to group $group"
    }
  fi
  log_info "Added user $username to group $group"
}

# =====================================================================================
# Function: verify_nfs_exports
# Description: Verifies the current NFS export configuration by attempting to list them.
# Arguments:
#   None.
# Returns:
#   Exits with a fatal error if NFS exports cannot be verified.
# =====================================================================================
verify_nfs_exports() {
  # Attempt to list NFS exports verbosely; redirect output to null
  if ! exportfs -v >/dev/null 2>&1; then
    log_fatal "Failed to verify NFS exports"
  fi
  log_info "NFS exports verified"
}

# =====================================================================================
# Function: zfs_pool_exists
# Description: Checks if a ZFS pool with the given name exists on the system.
# Arguments:
#   $1 (pool) - The name of the ZFS pool to check.
# Returns:
#   0 if the ZFS pool exists, 1 otherwise.
# =====================================================================================
zfs_pool_exists() {
  local pool="$1" # ZFS pool name to check
  # List ZFS pools and check if the specified pool name exists
  if zpool list -H -o name | grep -q "^$pool$"; then
    return 0 # Pool exists
  fi
  return 1 # Pool does not exist
}

# =====================================================================================
# Function: zfs_dataset_exists
# Description: Checks if a ZFS dataset with the given name exists on the system.
# Arguments:
#   $1 (dataset) - The full name of the ZFS dataset to check (e.g., "pool/dataset").
# Returns:
#   0 if the ZFS dataset exists, 1 otherwise.
# =====================================================================================
zfs_dataset_exists() {
  local dataset="$1" # ZFS dataset name to check
  # List ZFS datasets and check if the specified dataset name exists
  if zfs list -H -o name | grep -q "^$dataset$"; then
    return 0 # Dataset exists
  fi
  return 1 # Dataset does not exist
}
# =====================================================================================
# Function: is_command_available
# Description: Checks if a command is available inside a specified LXC container.
# Arguments:
#   $1 (CTID) - The container ID.
#   $2 (command_name) - The name of the command to check.
# Returns:
#   0 if the command is available, 1 otherwise.
# =====================================================================================
is_command_available() {
    local CTID="$1"
    local command_name="$2"

    log_debug "Checking for command '$command_name' in CTID $CTID..."
    if pct_exec "$CTID" command -v "$command_name" &> /dev/null; then
        log_debug "Command '$command_name' found in CTID $CTID."
        return 0
    else
        log_debug "Command '$command_name' not found in CTID $CTID."
        return 1
    fi
}

# =====================================================================================
# Function: cache_and_get_file
# Description: Downloads a file from a URL to a local cache directory if it doesn't
#              already exist and returns the path to the cached file.
# Arguments:
#   $1 (URL) - The URL of the file to download.
#   $2 (cache_dir) - The directory to store the cached file.
# Returns:
#   Echoes the full path to the cached file and returns 0 on success.
#   Returns a non-zero value if the download fails.
# =====================================================================================
cache_and_get_file() {
    local url="$1"
    local cache_dir="$2"
    local filename

    # Extract filename from the URL
    filename=$(basename "$url")
    local cached_file_path="${cache_dir}/${filename}"

    # Check if the file is already cached
    if [ -f "$cached_file_path" ]; then
        log_info "File '$filename' found in cache: $cached_file_path"
        echo "$cached_file_path"
        return 0
    fi

    # Create the cache directory if it doesn't exist
    mkdir -p "$cache_dir"

    # Download the file
    log_info "Downloading '$filename' from '$url' to '$cache_dir'..."
    if wget -qO "$cached_file_path" "$url"; then
        log_success "Successfully downloaded '$filename' to '$cached_file_path'"
        echo "$cached_file_path"
        return 0
    else
        log_error "Failed to download file from '$url'"
        # Clean up partially downloaded file
        rm -f "$cached_file_path"
        return 1
    fi
}
# =====================================================================================
# Function: is_nvidia_installed_robust
# Description: A robust check to see if the NVIDIA feature is installed.
# Arguments:
#   $1 (CTID) - The container ID.
# Returns:
#   0 if the feature is installed, 1 otherwise.
# =====================================================================================
is_nvidia_installed_robust() {
    local CTID="$1"
    log_info "--- Running Robust NVIDIA Installation Diagnostics for CTID $CTID ---"

    # 1. Check for nvidia-smi in common locations
    local nvidia_smi_path
    nvidia_smi_path=$(pct_exec "$CTID" find /usr/bin /usr/local/bin /opt -name "nvidia-smi" 2>/dev/null | head -n 1)

    if [ -z "$nvidia_smi_path" ]; then
        log_info "NVIDIA feature not installed: nvidia-smi binary not found."
        return 1
    fi
    log_info "Found 'nvidia-smi' binary at: $nvidia_smi_path"

    # 2. Check driver version
    local driver_version
    driver_version=$(pct_exec "$CTID" "$nvidia_smi_path" --query-gpu=driver_version --format=csv,noheader | head -n 1)

    if [ -z "$driver_version" ]; then
        log_info "NVIDIA feature not installed: Unable to query driver version."
        return 1
    fi
    log_info "NVIDIA driver version: $driver_version"

    # 3. Check for CUDA directory
    if ! pct_exec "$CTID" test -d /usr/local/cuda; then
        log_info "NVIDIA feature not installed: CUDA directory /usr/local/cuda does not exist."
        return 1
    fi
    log_info "CUDA directory /usr/local/cuda found."

    log_info "NVIDIA feature is already installed and configured correctly."
    log_info "--- End Robust NVIDIA Installation Diagnostics ---"
    return 0
}

# =====================================================================================
# Function: _check_docker_installed
# Description: Private function to check if the Docker feature is installed.
# Arguments:
#   $1 (CTID) - The container ID.
# Returns:
#   0 if the feature is installed, 1 otherwise.
# =====================================================================================
_check_docker_installed() {
    local CTID="$1"
    
    if ! is_command_available "$CTID" "docker"; then
        log_info "Docker feature not installed: docker command not found."
        return 1
    fi

    if ! pct_exec "$CTID" systemctl is-active --quiet docker; then
        log_info "Docker feature not installed: docker service is not active."
        return 1
    fi

    log_info "Docker feature is already installed and active."
    return 0
}

# =====================================================================================
# Function: _check_base_setup_installed
# Description: Private function to check if the base_setup feature is installed.
# Arguments:
#   $1 (CTID) - The container ID.
# Returns:
#   0 if the feature is installed, 1 otherwise.
# =====================================================================================
_check_base_setup_installed() {
    local CTID="$1"
    
    local essential_packages=("curl" "wget" "vim" "htop" "jq" "git" "rsync" "s-tui" "gnupg" "locales")
    for pkg in "${essential_packages[@]}"; do
        if ! is_command_available "$CTID" "$pkg"; then
            log_info "Base setup not complete: Essential package '$pkg' is missing."
            return 1
        fi
    done

    if ! pct_exec "$CTID" locale | grep -q "LANG=en_US.UTF-8"; then
        log_info "Base setup not complete: Locale is not set to en_US.UTF-8."
        return 1
    fi

    log_info "Base setup feature is already installed."
    return 0
}

# =====================================================================================
# Function: _check_ollama_installed
# Description: Private function to check if the Ollama feature is installed.
# Arguments:
#   $1 (CTID) - The container ID.
# Returns:
#   0 if the feature is installed, 1 otherwise.
# =====================================================================================
_check_ollama_installed() {
    local CTID="$1"
    
    if is_command_available "$CTID" "ollama"; then
        log_info "Ollama feature is already installed."
        return 0
    fi

    log_info "Ollama feature not installed: ollama command not found."
    return 1
}

# =====================================================================================
# Function: _check_python_api_service_installed
# Description: Private function to check if the python_api_service feature is installed.
# Arguments:
#   $1 (CTID) - The container ID.
# Returns:
#   0 if the feature is installed, 1 otherwise.
# =====================================================================================
_check_python_api_service_installed() {
    local CTID="$1"
    
    if ! is_command_available "$CTID" "python3"; then
        log_info "Python API service not installed: python3 command not found."
        return 1
    fi

    if ! is_command_available "$CTID" "pip3"; then
        log_info "Python API service not installed: pip3 command not found."
        return 1
    fi

    if ! pct_exec "$CTID" python3 -c "import venv" &> /dev/null; then
        log_info "Python API service not installed: venv module not found."
        return 1
    fi

    log_info "Python API service feature is already installed."
    return 0
}

# =====================================================================================
# Function: _check_vllm_installed
# Description: Private function to check if the vLLM feature is installed.
# Arguments:
#   $1 (CTID) - The container ID.
# Returns:
#   0 if the feature is installed, 1 otherwise.
# =====================================================================================
_check_vllm_installed() {
    local CTID="$1"
    local vllm_dir="/opt/vllm"
    
    if ! pct_exec "$CTID" test -d "$vllm_dir"; then
        log_info "vLLM feature not installed: vLLM directory not found."
        return 1
    fi

    if ! pct_exec "$CTID" test -f "${vllm_dir}/bin/vllm"; then
        log_info "vLLM feature not installed: vllm executable not found."
        return 1
    fi

    if ! pct_exec "$CTID" "${vllm_dir}/bin/python" -c "import vllm" &> /dev/null; then
        log_info "vLLM feature not installed: vllm package could not be imported."
        return 1
    fi

    log_info "vLLM feature is already installed."
    return 0
}

# =====================================================================================
# Function: is_feature_installed
# Description: Checks if a specific feature is already installed in a container.
# Arguments:
#   $1 (CTID) - The container ID.
#   $2 (feature_name) - The name of the feature to check (e.g., "nvidia").
# Returns:
#   0 if the feature is installed, 1 otherwise.
# =====================================================================================
is_feature_installed() {
    local CTID="$1"
    local feature_name="$2"

    log_info "Checking if feature '$feature_name' is installed in CTID $CTID..."

    case "$feature_name" in
        "nvidia")
            is_nvidia_installed_robust "$CTID"
            ;;
        "docker")
            _check_docker_installed "$CTID"
            ;;
        "base_setup")
            _check_base_setup_installed "$CTID"
            ;;
        "ollama")
            _check_ollama_installed "$CTID"
            ;;
        "python_api_service")
            _check_python_api_service_installed "$CTID"
            ;;
        "vllm")
            _check_vllm_installed "$CTID"
            ;;
        *)
            log_warn "No installation check defined for feature '$feature_name'. Assuming not installed."
            return 1
            ;;
    esac
}
# =====================================================================================
# Function: is_feature_present_on_container
# Description: Recursively checks if a feature is present on a container, including its templates.
# Arguments:
#   $1 (CTID) - The container ID to check.
#   $2 (feature_name) - The name of the feature to look for.
# Returns:
#   0 if the feature is found, 1 otherwise.
# =====================================================================================
is_feature_present_on_container() {
    local ctid="$1"
    local feature_name="$2"
    local features
    
    # Get the features for the current container
    features=$(jq_get_array "$ctid" ".features[]" || echo "")
    
    # Check if the feature is in the list of features for this container
    if [[ " ${features[*]} " =~ " ${feature_name} " ]]; then
        log_info "Feature '$feature_name' found directly on CTID $ctid."
        return 0
    fi
    
    # Get the parent template ID, if it exists
    local parent_ctid
    parent_ctid=$(jq_get_value "$ctid" ".clone_from_ctid" || echo "")
    
    # If there is a parent, recursively check it for the feature
    if [ -n "$parent_ctid" ]; then
        log_info "Feature '$feature_name' not found on CTID $ctid. Checking parent template: $parent_ctid."
        is_feature_present_on_container "$parent_ctid" "$feature_name"
        return $?
    fi
    
    # If there is no parent and the feature was not found, return 1
    log_info "Feature '$feature_name' not found on CTID $ctid or any of its parents."
    return 1
}