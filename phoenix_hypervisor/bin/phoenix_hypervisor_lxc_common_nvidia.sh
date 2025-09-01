#!/bin/bash
set -x
source "$(dirname "$0")/phoenix_hypervisor_lxc_common_loghelpers.sh"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# Add a diagnostic log to confirm the settings
echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] phoenix_hypervisor_lxc_common_nvidia.sh: LANG is set to: $LANG" | tee -a "$MAIN_LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] phoenix_hypervisor_lxc_common_nvidia.sh: LC_ALL is set to: $LC_ALL" | tee -a "$MAIN_LOG_FILE"

#
# File: phoenix_hypervisor_lxc_common_nvidia.sh
# Description: This script automates the configuration of NVIDIA GPU passthrough and driver installation
#              within a Proxmox LXC container. It ensures the container can access and utilize
#              NVIDIA GPUs from the host system, and installs the necessary NVIDIA drivers and CUDA toolkit.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# ### Usage
# To execute this script, provide the Container ID (CTID) as a command-line argument and set the
# following environment variables:
#
# ```bash
# CTID=<CTID> \
# GPU_ASSIGNMENT="<comma_separated_gpu_indices | none>" \
# NVIDIA_DRIVER_VERSION="<nvidia_driver_version>" \
# NVIDIA_REPO_URL="<nvidia_apt_repository_url>" \
# ./phoenix_hypervisor_lxc_common_nvidia.sh <CTID> <GPU_ASSIGNMENT> <NVIDIA_DRIVER_VERSION> <NVIDIA_REPO_URL>
# ```
#
# ### Requirements
# *   **Proxmox Host Environment:** The script must be run on a Proxmox host.
# *   **`pct` command:** Proxmox Container Toolkit command-line utility for LXC management.
# *   **`curl` or `wget`:** Required inside the LXC container for downloading the NVIDIA driver runfile.
# *   **`jq` (Optional):** May be used for complex JSON parsing in future iterations, though not currently required.
#
# ### Exit Codes
# *   **0:** Script executed successfully.
# *   **1:** General error or unhandled exception.
# *   **2:** Invalid input or missing arguments/environment variables.
# *   **3:** Target LXC container does not exist.
# *   **4:** Host-side configuration error (e.g., LXC config file not found).
# *   **5:** Error during NVIDIA software installation within the container.
# *   **6:** Container restart operation failed.

# --- Global Variables and Constants ---

# --- Logging Functions ---
# These functions are now sourced from phoenix_hypervisor_lxc_common_loghelpers.sh

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

log_info "IMPORTANT: Ensure 'nvidia-persistenced' service is running on the Proxmox host for proper GPU device access within LXC containers."

# --- Script Variables ---
CTID=""
GPU_ASSIGNMENT=""
NVIDIA_DRIVER_VERSION=""
NVIDIA_REPO_URL=""

### Function: parse_arguments
# Purpose: Parses command-line arguments to extract the Container ID (CTID) and NVIDIA-related variables.
# Content:
# *   Checks if exactly one argument is provided.
# *   If not, logs a usage error and exits with code 2.
# *   Assigns the argument to the `CTID` variable.
# *   Logs the successfully received arguments.
parse_arguments() {
    if [ "$#" -ne 4 ]; then
        log_error "Usage: $0 <CTID> <GPU_ASSIGNMENT> <NVIDIA_DRIVER_VERSION> <NVIDIA_REPO_URL>"
        exit_script 2
    fi
    CTID="$1"
    GPU_ASSIGNMENT="$2"
    NVIDIA_DRIVER_VERSION="$3"
    NVIDIA_REPO_URL="$4"
    log_info "Received CTID: $CTID, GPU_ASSIGNMENT: $GPU_ASSIGNMENT, NVIDIA_DRIVER_VERSION: $NVIDIA_DRIVER_VERSION, NVIDIA_REPO_URL: $NVIDIA_REPO_URL"
}

### Function: validate_inputs
# Purpose: Validates all necessary inputs, including the CTID and required arguments,
#          to ensure the script can proceed with configuration.
# Content:
# *   Verifies that `CTID` is a positive integer; otherwise, logs a fatal error and exits.
# *   Checks if `GPU_ASSIGNMENT` is set and not empty. If missing, logs a fatal error and exits.
# *   Logs a success message if all input validations pass.
validate_inputs() {
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_error "FATAL: Invalid CTID '$CTID'. Must be a positive integer."
        exit_script 2
    fi
    if [ -z "$GPU_ASSIGNMENT" ]; then
        log_error "FATAL: GPU_ASSIGNMENT is not set or empty."
        exit_script 2
    fi
    log_info "Input validation passed."
}

### Function: check_container_exists
# Purpose: Confirms the existence of the target LXC container on the Proxmox host.
# Content:
# *   Logs the initiation of the container existence check for the given `CTID`.
# *   Executes `pct status "$CTID"` to determine if the container is recognized by Proxmox.
# *   If the `pct status` command fails (non-zero exit code), logs a fatal error and exits with code 3.
# *   Logs a confirmation message if the container is found.
check_container_exists() {
    log_info "Checking for existence of container CTID: $CTID"
    if ! pct status "$CTID" > /dev/null 2>&1; then
        log_error "FATAL: Container $CTID does not exist."
        exit_script 3
    fi
    log_info "Container $CTID exists."
}

### Function: configure_host_gpu_passthrough
# Purpose: Modifies the LXC container's configuration file on the Proxmox host to bind-mount
#          the necessary NVIDIA devices from the host into the container's filesystem.
#          This enables the container to access physical GPUs.
# Content:
# *   Defines the path to the LXC configuration file (`/etc/pve/lxc/<CTID>.conf`).
# *   Verifies the existence of the LXC configuration file; exits if not found.
# *   Initializes a list of standard NVIDIA devices (`/dev/nvidiactl`, `/dev/nvidia-uvm`, etc.).
# *   **GPU Assignment Handling:**
#     *   If `GPU_ASSIGNMENT` is not "none", it parses the comma-separated GPU indices.
#     *   For each assigned GPU index, constructs the device path (`/dev/nvidia<IDX>`).
#     *   Checks if the device exists on the host and adds an `lxc.mount.entry` for it.
#     *   Logs a warning if an assigned GPU device is not found on the host.
# *   **Standard Device Handling:**
#     *   Iterates through the `standard_devices` list.
#     *   Determines if the device is a file or a directory (e.g., `/dev/nvidia-caps` is a directory).
#     *   Checks if the standard device exists on the host and adds an `lxc.mount.entry` for it.
#     *   Logs a warning if a standard NVIDIA device is not found on the host.
# *   **Applying Mount Entries:**
#     *   Iterates through the collected `mount_entries`.
#     *   For each entry, checks if it already exists in the LXC configuration file to ensure idempotency.
#     *   If the entry does not exist, it is appended to the configuration file.
#     *   Logs whether an entry was appended or already present.
# *   Logs completion of the host GPU passthrough configuration.
configure_host_gpu_passthrough() {
    log_info "Configuring host GPU passthrough for container CTID: $CTID"
    local lxc_conf_file="/etc/pve/lxc/${CTID}.conf"
    if [ ! -f "$lxc_conf_file" ]; then
        log_error "FATAL: LXC config file not found at $lxc_conf_file."
        exit_script 4
    fi

    # Define the required lxc.mount.entry lines
    local mount_entries=(
        "lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file"
        "lxc.mount.entry: /dev/nvidia1 dev/nvidia1 none bind,optional,create=file"
        "lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file"
        "lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file"
        "lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file"
    )

    # Add cgroup device allow rules for NVIDIA devices
    local cgroup_entries=(
        "lxc.cgroup2.devices.allow: c 195:* rwm" # NVIDIA devices
        "lxc.cgroup2.devices.allow: c 243:* rwm" # NVIDIA UVM devices
    )

    # Apply mount entries
    for entry in "${mount_entries[@]}"; do
        if ! grep -qF "$entry" "$lxc_conf_file"; then
            log_info "Adding mount entry: $entry"
            echo "$entry" >> "$lxc_conf_file"
            if [ $? -ne 0 ]; then
                log_error "FATAL: Failed to add mount entry '$entry' for CTID $CTID."
                exit_script 4
            fi
        else
            log_info "Mount entry '$entry' already exists for CTID $CTID. Skipping."
        fi
    done

    # Apply cgroup entries
    for entry in "${cgroup_entries[@]}"; do
        if ! grep -qF "$entry" "$lxc_conf_file"; then
            log_info "Adding cgroup entry: $entry"
            echo "$entry" >> "$lxc_conf_file"
            if [ $? -ne 0 ]; then
                log_error "FATAL: Failed to add cgroup entry '$entry' for CTID $CTID."
                exit_script 4
            fi
        else
            log_info "Cgroup entry '$entry' already exists for CTID $CTID. Skipping."
        fi
    done

    log_info "Host GPU passthrough configuration complete."
}

verify_device_passthrough() {
    log_info "Verifying GPU device passthrough for container CTID: $CTID"
    local lxc_conf_file="/etc/pve/lxc/${CTID}.conf"
    local config_content
    config_content=$(cat "$lxc_conf_file")
    local all_verified=true

    # Define the expected lxc.mount.entry lines
    local expected_mount_entries=(
        "lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file"
        "lxc.mount.entry: /dev/nvidia1 dev/nvidia1 none bind,optional,create=file"
        "lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file"
        "lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file"
        "lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file"
    )

    # Define the expected cgroup device allow rules for NVIDIA devices
    local expected_cgroup_entries=(
        "lxc.cgroup2.devices.allow: c 195:* rwm" # NVIDIA devices
        "lxc.cgroup2.devices.allow: c 243:* rwm" # NVIDIA UVM devices
    )

    local entries_to_check=()

    if [ "$GPU_ASSIGNMENT" != "none" ]; then
        entries_to_check+=("${expected_mount_entries[@]}")
        entries_to_check+=("${expected_cgroup_entries[@]}")
    else
        log_info "GPU_ASSIGNMENT is 'none'. No GPU devices to verify."
        return 0
    fi

    for expected_line in "${entries_to_check[@]}"; do
        if echo "$config_content" | grep -qF "$expected_line"; then
            log_info "Verification successful: '$expected_line' found in $lxc_conf_file"
        else
            log_error "Verification failed: '$expected_line' NOT found in $lxc_conf_file"
            all_verified=false
        fi
    done

    if ! "$all_verified"; then
        log_error "FATAL: One or more required GPU device entries are missing from LXC configuration."
        exit_script 4
    fi
    log_info "All required GPU device passthrough entries verified successfully."
}


### Function: main
# Purpose: Serves as the entry point for the script, orchestrating the entire
#          NVIDIA GPU configuration process for an LXC container.
# Content:
# *   Calls `parse_arguments` to retrieve the `CTID` from command-line input.
# *   Invokes `validate_inputs` to ensure all required arguments and environment variables are valid.
# *   Executes `check_container_exists` to confirm the target container is present on the host.
# *   Calls `configure_host_gpu_passthrough` to set up device mounts in the LXC configuration.
# *   Calls `exit_script 0` upon successful completion of all steps.
main() {
    parse_arguments "$@"
    validate_inputs
    check_container_exists

    log_info "--- Host-side NVIDIA Driver and Kernel Module Status ---"
    log_info "Checking host NVIDIA driver status..."
    if command -v nvidia-smi &> /dev/null; then
        log_info "Host nvidia-smi output:"
        nvidia-smi | while IFS= read -r line; do log_info "HOST_NVIDIA_SMI: $line"; done
    else
        log_info "nvidia-smi not found on host."
    fi
    log_info "Checking host kernel modules..."
    lsmod | grep -i nvidia | while IFS= read -r line; do log_info "HOST_LSMOD_NVIDIA: $line"; done
    log_info "Checking nvidia-persistenced service status on host..."
    if systemctl is-active --quiet nvidia-persistenced; then
        log_info "nvidia-persistenced is running on host."
    else
        log_info "nvidia-persistenced is NOT running on host."
    fi
    log_info "--- End Host-side NVIDIA Driver and Kernel Module Status ---"

    log_info "LXC Container Configuration for CTID $CTID:"
    pct config "$CTID" | while IFS= read -r line; do log_info "LXC_CONFIG: $line"; done

    configure_host_gpu_passthrough
    verify_device_passthrough
    exit_script 0
}

# Call the main function
main "$@"
