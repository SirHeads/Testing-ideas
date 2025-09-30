#!/bin/bash
#
# File: phoenix_hypervisor_common_utils.sh
# Description: This script provides a centralized library of shell functions and environment settings for all
#              Phoenix Hypervisor scripts. It is designed to be sourced by other scripts to ensure a consistent
#              execution environment, standardized logging, and robust error handling. The script includes
#              utilities for logging, interacting with Proxmox tools (`pct`, `qm`), querying JSON configuration
#              files, and performing common system checks. This modular approach promotes code reuse and
#              maintainability across the entire hypervisor management system.
#
# Dependencies:
#   - jq: A command-line JSON processor used to parse the configuration files.
#   - Proxmox VE command-line tools: `pct`, `qm`, `pvesm`.
#   - Standard Linux utilities: `dpkg-query`, `ping`, `ip`, `zfs`, `zpool`, `usermod`, `exportfs`, `wget`, `curl`, `gpg`, `apt-get`.
#
# Inputs:
#   - PHOENIX_DEBUG: An environment variable that, when set to "true", enables detailed debug logging.
#   - DRY_RUN: An environment variable that, when set to "true", prevents the script from making any actual changes to the system.
#   - Function arguments for the various utility functions provided by this script.
#
# Outputs:
#   - Log messages to stdout and to the main log file at /var/log/phoenix_hypervisor.log.
#   - Queried values from JSON configuration files.
#   - Exit codes indicating the success or failure of the functions.
#
# Version: 1.1.0
# Author: Phoenix Hypervisor Team

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Global Constants ---
export HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"
export LXC_CONFIG_SCHEMA_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json"
export MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"

# --- Dynamic LXC_CONFIG_FILE Path ---
# This logic allows the script to be used both on the host and inside a container's temporary execution environment.
# It dynamically sets the path to the LXC configuration file based on the script's execution context.
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
# Description: Logs a debug message to stdout and the main log file. This function is only
#              active when the `PHOENIX_DEBUG` environment variable is set to "true".
#
# Arguments:
#   $@ - The message to log.
#
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
# Description: Logs an informational message to stdout and the main log file. This is the
#              standard logging function for general-purpose messages.
#
# Arguments:
#   $@ - The message to log.
#
# Returns:
#   None.
# =====================================================================================
log_info() {
    # Log the informational message with timestamp and script name
    echo -e "${COLOR_GREEN}$(date '+%Y-%m-%d %H:%M:%S') [INFO] $(basename "$0"): $*${COLOR_RESET}" | tee -a "$MAIN_LOG_FILE" >&2
}

# =====================================================================================
# Function: log_success
# Description: Logs a success message to stdout and the main log file. This is used to
#              indicate that a significant operation has completed successfully.
#
# Arguments:
#   $@ - The message to log.
#
# Returns:
#   None.
# =====================================================================================
log_success() {
    # Log the success message with timestamp and script name
    echo -e "${COLOR_GREEN}$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $(basename "$0"): $*${COLOR_RESET}" | tee -a "$MAIN_LOG_FILE" >&2
}

# =====================================================================================
# Function: log_warn
# Description: Logs a warning message to stderr and the main log file. This is used for
#              non-fatal issues that should be brought to the user's attention.
#
# Arguments:
#   $@ - The message to log.
#
# Returns:
#   None.
# =====================================================================================
log_warn() {
	# Log the warning message with timestamp and script name to stderr
	echo -e "${COLOR_YELLOW}$(date '+%Y-%m-%d %H:%M:%S') [WARN] $(basename "$0"): $*${COLOR_RESET}" | tee -a "$MAIN_LOG_FILE" >&2
}

# =====================================================================================
# Function: log_error
# Description: Logs an error message to stderr and the main log file. This is used for
#              recoverable errors that do not require the script to exit.
#
# Arguments:
#   $@ - The message to log.
#
# Returns:
#   None.
# =====================================================================================
log_error() {
    # Log the error message with timestamp and script name to stderr
    echo -e "${COLOR_RED}$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $(basename "$0"): $*${COLOR_RESET}" | tee -a "$MAIN_LOG_FILE" >&2
}

# =====================================================================================
# Function: log_fatal
# Description: Logs a fatal error message to stderr and the main log file, and then exits
#              the script with a status code of 1. This is used for unrecoverable errors.
#
# Arguments:
#   $@ - The message to log.
#
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
# Description: Ensures that the log directory exists and that the log file is available for
#              writing. This function is called at the beginning of the main orchestrator script.
#
# Arguments:
#   $1 - The full path to the log file.
#
# Returns:
#   None. The function will exit with a fatal error if the log directory or file cannot be created.
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
# Description: Logs multi-line output from a variable or command while preserving its
#              original formatting. This function is designed to be used with pipes.
#
# Arguments:
#   None. Reads from stdin.
#
# Returns:
#   None.
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
# Description: Executes a command inside a specified LXC container using `pct exec`. This
#              function is a robust wrapper that handles errors and ensures that commands
#              are run with the appropriate privileges. It also includes context-aware logic
#              to execute commands directly when running inside the container's temporary
#              execution environment.
#
# Arguments:
#   $1 - The CTID of the container.
#   $@ - The command and its arguments to execute inside the container.
#
# Returns:
#   0 on success, or the exit code of the failed command on failure.
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
        local exit_code=0
        output=$(pct exec "$ctid" -- "${cmd_args[@]}" 2>&1) || exit_code=$?
        if [ $exit_code -ne 0 ]; then
            log_error "Command failed in CTID $ctid with exit code $exit_code: '${cmd_args[@]}'"
            log_error "Output:\n$output"
            return $exit_code
        fi
        echo "$output"
    fi
    return 0
}

# =====================================================================================
# Function: jq_get_value
# Description: A robust wrapper for `jq` that retrieves a specific value from the LXC JSON
#              configuration file for a given CTID. This function simplifies the process of
#              querying the configuration and includes error handling.
#
# Arguments:
#   $1 - The CTID of the container.
#   $2 - The `jq` query string to execute.
#
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
# Description: A robust wrapper for `jq` that retrieves all elements of a JSON array from the
#              LXC configuration file for a given CTID.
#
# Arguments:
#   $1 - The CTID of the container.
#   $2 - The `jq` query string that selects the array.
#
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
# Description: A robust wrapper for executing `pct` commands. It handles logging, error
#              handling, and dry-run mode, ensuring that all container operations are
#              consistently managed.
#
# Arguments:
#   $@ - The arguments to pass to the `pct` command.
#
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
   output=$(pct "${pct_args[@]}" 2>&1) || exit_code=$?

   log_debug "pct command output:\n$output"
   log_debug "pct command exit code: $exit_code"

   if [ $exit_code -ne 0 ]; then
       if [[ "${pct_args[0]}" == "resize" && "$output" == *"disk is already at specified size"* ]]; then
           log_info "Ignoring non-fatal error for 'pct resize': $output"
       elif [[ "${pct_args[0]}" == "start" && "$output" == *"explicitly configured lxc.apparmor.profile"* ]]; then
           log_error "AppArmor profile conflict detected for CTID ${pct_args[1]}."
           log_error "Output:\n$output"
           # Decide if this should be a fatal error or just a warning
           return 1 # Treat as a fatal error for now
       else
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
# Description: A robust wrapper for `pct push` that includes retries and verification. This
#              function is used to reliably copy files from the host to a container.
#
# Arguments:
#   $1 - The CTID of the container.
#   $2 - The path of the file on the host.
#   $3 - The destination path in the container.
#   $4 - Optional: Maximum number of push attempts (default: 3).
#   $5 - Optional: Delay in seconds between retries (default: 5).
#
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
# Description: Ensures that the NVIDIA CUDA repository is correctly configured in the specified
#              container. This function is idempotent and will not make any changes if the
#              repository is already configured.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if the repository setup fails.
# =====================================================================================
ensure_nvidia_repo_is_configured() {
    local ctid="$1"
    log_info "Ensuring NVIDIA CUDA repository is configured in CTID $ctid..."

    local nvidia_repo_url
    nvidia_repo_url=$(jq_get_value "$ctid" ".nvidia_repo_url")
    local cuda_keyring_path="/usr/share/keyrings/cuda-archive-keyring.gpg"
    local expected_repo_line="deb [signed-by=${cuda_keyring_path}] ${nvidia_repo_url} /"
    local repo_file_path="/etc/apt/sources.list.d/cuda.list"

    # Idempotency Check: Verify if the repo is already correctly configured
    if pct_exec "$ctid" -- test -f "$repo_file_path" && \
       pct_exec "$ctid" -- grep -Fxq -- "${expected_repo_line}" "$repo_file_path" && \
       pct_exec "$ctid" -- test -f "$cuda_keyring_path"; then
        log_info "NVIDIA CUDA repository is already correctly configured. Skipping."
        return 0
    fi

    log_info "NVIDIA CUDA repository not configured or misconfigured. Proceeding with setup."

    local os_version
    os_version=$(echo "$nvidia_repo_url" | grep -oP 'ubuntu\K[0-9]{4}')
    local cuda_pin_url="${nvidia_repo_url}cuda-ubuntu${os_version}.pin"
    local cuda_key_url="${nvidia_repo_url}3bf863cc.pub"

    # Setup repository and keyring
    pct_exec "$ctid" -- wget -qO "/etc/apt/preferences.d/cuda-repository-pin-600" "$cuda_pin_url"
    pct_exec "$ctid" -- bash -c "curl -fsSL \"$cuda_key_url\" | gpg --dearmor -o \"$cuda_keyring_path\""
    pct_exec "$ctid" -- chmod 644 "$cuda_keyring_path"
    pct_exec "$ctid" -- bash -c "echo \"$expected_repo_line\" > \"$repo_file_path\""
    
    log_info "Updating package lists in CTID $ctid..."
    pct_exec "$ctid" -- apt-get update
    log_success "NVIDIA CUDA repository configured successfully for CTID $ctid."
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
# Description: Ensures that the script is being run with root privileges. This is a critical
#              security check for scripts that perform system-level operations.
#
# Arguments:
#   None.
#
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
#
# Arguments:
#   $1 - The name of the package to check.
#
# Returns:
#   0 if the package is installed, 1 otherwise.
# =====================================================================================
check_package() {
  local package="$1" # Capture the package name
  # Query dpkg for the package status and check if it's "install ok installed"
  dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"
}

# =====================================================================================
# Function: check_network_connectivity
# Description: Verifies network connectivity to a specified host by pinging it with retries.
#              This is a useful utility for ensuring that the system has access to required
#              network resources.
#
# Arguments:
#   $1 - The hostname or IP address to ping.
#
# Returns:
#   0 on successful connectivity. Exits with a fatal error on failure after retries.
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

# =====================================================================================
# Function: check_internet_connectivity
# Description: Verifies general internet connectivity by pinging a well-known DNS server
#              (8.8.8.8) with retries.
#
# Arguments:
#   None.
#
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
# Description: Checks if any network interface on the system is configured within a given
#              IPv4 subnet. This is useful for verifying network configurations.
#
# Arguments:
#   $1 - The IPv4 subnet in CIDR notation (e.g., "192.168.1.0/24").
#
# Returns:
#   0 if an interface is found in the subnet, 1 otherwise. Exits with a fatal error for
#   invalid subnet format.
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
# Description: Creates a ZFS dataset with a specified mountpoint and optional additional
#              properties. This is a key utility for managing storage in the hypervisor.
#
# Arguments:
#   $1 - The name of the ZFS pool.
#   $2 - The name of the dataset to create within the pool.
#   $3 - The desired mountpoint for the new dataset.
#   $@ - Optional additional ZFS properties to set (e.g., "compression=lz4").
#
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
#
# Arguments:
#   $1 - The full name of the ZFS dataset (e.g., "pool/dataset").
#   $@ - A list of properties to set (e.g., "compression=lz4", "sharenfs=on").
#
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
# Description: Configures an NFS export for a given dataset by adding an entry to
#              `/etc/exports` and refreshing the NFS export list.
#
# Arguments:
#   $1 - The name of the ZFS dataset being exported (for logging purposes).
#   $2 - The mountpoint of the dataset to be exported.
#   $3 - The network subnet allowed to access the export (e.g., "192.168.1.0/24").
#   $4 - NFS export options (e.g., "rw,sync,no_subtree_check").
#
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

# =====================================================================================
# Function: retry_command
# Description: Executes a given command, retrying it up to a maximum number of attempts
#              if it fails. This is a useful utility for handling transient errors.
#
# Arguments:
#   $1 - The command string to execute.
#
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
#
# Arguments:
#   $1 - The username to add to the group.
#   $2 - The name of the group.
#
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
#
# Arguments:
#   None.
#
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
#
# Arguments:
#   $1 - The name of the ZFS pool to check.
#
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
#
# Arguments:
#   $1 - The full name of the ZFS dataset to check (e.g., "pool/dataset").
#
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
#
# Arguments:
#   $1 - The CTID of the container.
#   $2 - The name of the command to check.
#
# Returns:
#   0 if the command is available, 1 otherwise.
# =====================================================================================
is_command_available() {
    local CTID="$1"
    local command_name="$2"
    
    log_debug "Checking for command '$command_name' in CTID $CTID..."
    
    # First, try the standard 'command -v' which is fast and checks the PATH
    if pct_exec "$CTID" command -v "$command_name" >/dev/null 2>&1; then
        log_debug "Command '$command_name' found in PATH for CTID $CTID."
        return 0
    fi
    
    # If not found in PATH, check for the file's existence in common locations using 'test -f'
    log_debug "Command '$command_name' not in PATH. Checking common locations with 'test -f' in CTID $CTID..."
    local search_paths=("/usr/bin" "/usr/sbin" "/bin" "/sbin" "/usr/local/bin" "/usr/local/sbin" "/opt/bin" "/usr/local/cuda/bin" "/usr/local/cuda-12.8/bin")
    
    for path in "${search_paths[@]}"; do
        if pct_exec "$CTID" test -f "${path}/${command_name}"; then
            log_debug "Command '$command_name' found at ${path}/${command_name} in CTID $CTID."
            return 0
        fi
    done

    log_debug "Command '$command_name' not found in CTID $CTID after full search."
    return 1
}

# =====================================================================================
# Function: cache_and_get_file
# Description: Downloads a file from a URL to a local cache directory if it doesn't
#              already exist and returns the path to the cached file.
#
# Arguments:
#   $1 - The URL of the file to download.
#   $2 - The directory to store the cached file.
#
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
# Description: A robust check to see if the NVIDIA feature is installed in a container.
#
# Arguments:
#   $1 - The CTID of the container.
#
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
# Description: Private function to check if the Docker feature is installed in a container.
#
# Arguments:
#   $1 - The CTID of the container.
#
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
# Description: Private function to check if the base_setup feature is installed in a container.
#
# Arguments:
#   $1 - The CTID of the container.
#
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
# Description: Private function to check if the Ollama feature is installed in a container.
#
# Arguments:
#   $1 - The CTID of the container.
#
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
#
# Arguments:
#   $1 - The CTID of the container.
#
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
# Description: Private function to check if the vLLM feature is installed in a container.
#
# Arguments:
#   $1 - The CTID of the container.
#
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
# Function: is_feature_present_on_container
# Description: Recursively checks if a feature is present on a container, including its templates.
#
# Arguments:
#   $1 - The CTID of the container to check.
#   $2 - The name of the feature to look for.
#
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
# =====================================================================================
# Function: wait_for_container_initialization
# Description: Waits for a container to have network connectivity.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   0 on success, exits with a fatal error on timeout.
# =====================================================================================
wait_for_container_initialization() {
    local ctid="$1"
    local timeout=60
    local end_time=$((SECONDS + timeout))

    log_info "Waiting for container $ctid to initialize (up to ${timeout}s)..."

    while [ $SECONDS -lt $end_time ]; do
        if pct_exec "$ctid" -- ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            log_success "Container $ctid is initialized and has network connectivity."
            return 0
        fi
        sleep 2
    done

    log_fatal "Timeout reached: Container $ctid did not initialize within $timeout seconds."
}
# =====================================================================================
# Function: verify_lxc_network_connectivity
# Description: Verifies network connectivity and DNS resolution within a container.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   0 if network is healthy, 1 otherwise.
# =====================================================================================
verify_lxc_network_connectivity() {
    local CTID="$1"
    log_info "Verifying network connectivity for CTID: $CTID..."
    local attempts=0
    local max_attempts=5
    local interval=10

    while [ "$attempts" -lt "$max_attempts" ]; do
        log_info "Attempting to resolve google.com (Attempt $((attempts + 1))/$max_attempts)..."
        if pct exec "$CTID" -- ping -c 1 google.com &> /dev/null; then
            log_info "DNS resolution and network connectivity are operational for CTID $CTID."
            return 0
        fi
        attempts=$((attempts + 1))
        if [ "$attempts" -lt "$max_attempts" ]; then
            log_info "Network check failed. Retrying in $interval seconds..."
            sleep "$interval"
        fi
    done

    log_error "Network connectivity check failed for CTID $CTID after $max_attempts attempts."
    return 1
}
# =====================================================================================
# Function: start_vm
# Description: Starts a Proxmox VM if it is not already running.
#
# Arguments:
#   $1 - The VMID of the VM to start.
#
# Returns:
#   None. Exits with a fatal error if the VM fails to start.
# =====================================================================================
start_vm() {
    local VMID="$1"
    log_info "Attempting to start VM $VMID..."

    if qm status "$VMID" | grep -q "status: running"; then
        log_info "VM $VMID is already running."
        return 0
    fi

    if ! run_qm_command start "$VMID"; then
        log_fatal "Failed to start VM $VMID."
    fi
    log_info "VM $VMID started successfully."
}

# =====================================================================================
# Function: wait_for_guest_agent
# Description: Waits for the QEMU guest agent to become responsive.
#
# Arguments:
#   $1 - The VMID of the VM.
#
# Returns:
#   None. Exits with a fatal error on timeout.
# =====================================================================================
wait_for_guest_agent() {
    local VMID="$1"
    log_info "Waiting for QEMU guest agent on VM $VMID..."
    local max_attempts=30
    local attempt=0
    local interval=10

    while [ $attempt -lt $max_attempts ]; do
        if qm agent "$VMID" ping 1>/dev/null 2>&1; then
            log_info "QEMU guest agent is responsive on VM $VMID."
            return 0
        fi
        log_info "Guest agent not ready yet. Retrying in $interval seconds... (Attempt $((attempt + 1))/$max_attempts)"
        sleep $interval
        attempt=$((attempt + 1))
    done

    log_fatal "Timeout waiting for QEMU guest agent on VM $VMID."
}

# =====================================================================================
# Function: apply_vm_features
# Description: Executes feature installation scripts inside the VM.
#
# Arguments:
#   $1 - The VMID of the VM.
#
# Returns:
#   None. Exits with a fatal error if a feature script fails.
# =====================================================================================
apply_vm_features() {
    local VMID="$1"
    log_info "Applying features for VMID: $VMID"
    
    local features
    features=$(jq -r ".vms[] | select(.vmid == ${VMID}) | .features[]?" "$VM_CONFIG_FILE")

    if [ -z "$features" ]; then
        log_info "No features to apply for VMID $VMID."
        return 0
    fi

    for feature in $features; do
        local feature_script_path="${PHOENIX_BASE_DIR}/bin/vm_features/feature_install_${feature}.sh"
        log_info "Applying feature: $feature ($feature_script_path)"

        if [ ! -f "$feature_script_path" ]; then
            log_fatal "Feature script not found at $feature_script_path."
        fi

        # Copy script to VM
        local vm_script_path="/tmp/feature_install_${feature}.sh"
        if ! run_qm_command push "$VMID" "$feature_script_path" "$vm_script_path"; then
            log_fatal "Failed to copy feature script '$feature' to VM $VMID."
        fi

        # Make script executable
        if ! qm agent "$VMID" exec -- /bin/chmod +x "$vm_script_path"; then
             log_fatal "Failed to make feature script '$feature' executable in VM $VMID."
        fi

        # Execute script
        if ! qm agent "$VMID" exec -- "$vm_script_path"; then
            log_fatal "Feature script '$feature' failed for VMID $VMID."
        fi
        
        # Cleanup script
        if ! qm agent "$VMID" exec -- /bin/rm "$vm_script_path"; then
            log_warn "Failed to remove feature script '$feature' from VM $VMID."
        fi
    done

    log_info "All features applied successfully for VMID $VMID."
}

# =====================================================================================
# Function: create_vm_snapshot
# Description: Creates a snapshot of a VM if a snapshot name is defined.
#
# Arguments:
#   $1 - The VMID of the VM.
#
# Returns:
#   None. Exits with a fatal error if snapshot creation fails.
# =====================================================================================
create_vm_snapshot() {
    local VMID="$1"
    log_info "Checking for snapshot creation for VMID: $VMID"
    
    local snapshot_name
    snapshot_name=$(jq -r ".vms[] | select(.vmid == ${VMID}) | .template_snapshot_name // \"\"" "$VM_CONFIG_FILE")

    if [ -z "$snapshot_name" ]; then
        log_info "No template_snapshot_name defined for VMID $VMID. Skipping snapshot creation."
        return 0
    fi

    if qm listsnapshot "$VMID" | grep -q "$snapshot_name"; then
        log_info "Snapshot '$snapshot_name' already exists for VMID $VMID. Skipping."
        return 0
    fi

    log_info "Creating snapshot '$snapshot_name' for VM $VMID..."
    if ! run_qm_command snapshot "$VMID" "$snapshot_name"; then
        log_fatal "Failed to create snapshot '$snapshot_name' for VMID $VMID."
    fi

    log_info "Snapshot '$snapshot_name' created successfully."
}