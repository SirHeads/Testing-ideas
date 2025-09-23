#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_nvidia.sh
# Description: Automates the configuration of NVIDIA GPU passthrough for an LXC container
#              on the Proxmox host, and then installs NVIDIA drivers and CUDA Toolkit
#              inside the container. This script is designed to be idempotent and is
#              typically called by the main orchestrator.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq, grep, echo, mv,
#               pct, apt-get, wget, basename, chmod, rm, bash, systemctl, nvidia-smi.
# Inputs:
#   $1 (CTID) - The container ID for the LXC container.
#   Configuration values from LXC_CONFIG_FILE: .gpu_assignment, .nvidia_runfile_url.
# Outputs:
#   LXC container configuration file modifications (`/etc/pve/lxc/<CTID>.conf`),
#   NVIDIA driver and CUDA Toolkit installation logs, nvidia-smi output for verification,
#   log messages to stdout and MAIN_LOG_FILE, exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Source common utilities ---
# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""

# =====================================================================================
# Function: parse_arguments
# Description: Parses the CTID from command-line arguments.
# =====================================================================================
# =====================================================================================
# Function: parse_arguments
# Description: Parses command-line arguments to extract the Container ID (CTID).
# Arguments:
#   $1 - The Container ID (CTID) for the LXC container.
# Returns:
#   Exits with status 2 if no CTID is provided.
# =====================================================================================
parse_arguments() {
    # Check if exactly one argument (CTID) is provided
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1" # Assign the first argument to CTID
    log_info "Executing NVIDIA feature for CTID: $CTID"
}

# =====================================================================================
# Function: configure_host_gpu_passthrough
# Description: Modifies the LXC container's configuration file on the Proxmox host to
#              bind-mount the necessary NVIDIA devices.
# =====================================================================================
# =====================================================================================
# Function: configure_host_gpu_passthrough
# Description: Configures NVIDIA GPU passthrough for the specified LXC container
#              on the Proxmox host. It modifies the container's configuration file
#              to bind-mount necessary NVIDIA devices and sets cgroup permissions.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if the LXC config file is not found or if
#   GPU assignment is missing. Restarts the container to apply changes.
# =====================================================================================
configure_host_gpu_passthrough() {
    log_info "Configuring host GPU passthrough for container CTID: $CTID"
    local lxc_conf_file="/etc/pve/lxc/${CTID}.conf"
    local gpu_assignment
    local changes_made=false

    gpu_assignment=$(jq_get_value "$CTID" ".gpu_assignment")
    if [ -z "$gpu_assignment" ] || [ "$gpu_assignment" == "none" ]; then
        log_info "No GPU assignment found for CTID $CTID. Skipping NVIDIA feature."
        exit_script 0
    fi

    if [ ! -f "$lxc_conf_file" ]; then
        log_fatal "LXC config file not found at $lxc_conf_file."
    fi

    local mount_entries=()
    local cgroup_entries=(
        "lxc.cgroup2.devices.allow: c 195:* rwm"
        "lxc.cgroup2.devices.allow: c 243:* rwm"
    )

    local standard_devices=("/dev/nvidiactl" "/dev/nvidia-uvm" "/dev/nvidia-uvm-tools")
    for device in "${standard_devices[@]}"; do
        if [ -e "$device" ]; then
            mount_entries+=("lxc.mount.entry: $device ${device#/} none bind,optional,create=file")
        else
            log_warn "Standard NVIDIA device $device not found on host. Skipping."
        fi
    done

    IFS=',' read -ra gpus <<< "$gpu_assignment"
    for gpu_idx in "${gpus[@]}"; do
        local nvidia_device="/dev/nvidia${gpu_idx}"
        if [ -e "$nvidia_device" ]; then
            mount_entries+=("lxc.mount.entry: $nvidia_device ${nvidia_device#/} none bind,optional,create=file")
        else
            log_warn "Assigned GPU device $nvidia_device not found on host. Skipping."
        fi
    done

    for entry in "${mount_entries[@]}" "${cgroup_entries[@]}"; do
        if ! grep -qF "$entry" "$lxc_conf_file"; then
            log_info "Adding entry to $lxc_conf_file: $entry"
            echo "$entry" >> "$lxc_conf_file"
            changes_made=true
        else
            log_info "Entry already exists in $lxc_conf_file: $entry"
        fi
    done

    log_info "Host GPU passthrough configuration complete for CTID $CTID."
    if [ "$changes_made" = true ]; then
        log_info "Restarting container CTID $CTID to apply GPU passthrough settings..."
        run_pct_command stop "$CTID"
        run_pct_command start "$CTID"
        log_info "Container CTID $CTID restarted successfully."
    else
        log_info "No changes made to container configuration. Skipping restart."
    fi
}

# =====================================================================================
# Function: wait_for_nvidia_device
# Description: Waits for the NVIDIA device node to appear in the container.
# Arguments:
#   $1 - CTID
#   $2 - Device path (e.g., /dev/nvidia0)
# Returns:
#   0 if the device is found within the timeout, 1 otherwise.
# =====================================================================================
wait_for_nvidia_device() {
    local ctid="$1"
    local device_path="/dev/nvidia0"
    local timeout=30
    local interval=2
    local elapsed_time=0

    log_info "Waiting for NVIDIA device to become available in CTID $ctid..."

    while [ $elapsed_time -lt $timeout ]; do
        if pct exec "$ctid" -- test -e "$device_path"; then
            log_info "NVIDIA device found in CTID $ctid."
            return 0
        fi
        sleep $interval
        elapsed_time=$((elapsed_time + interval))
    done

    log_fatal "Timeout reached. NVIDIA device not found in CTID $ctid after ${timeout} seconds."
    log_info "Contents of /dev/ in CTID $ctid:"
    pct exec "$ctid" -- ls -la /dev/
    return 1
}
# =====================================================================================
# Function: install_drivers_in_container
# Description: Installs the NVIDIA driver and CUDA toolkit inside the container.
# =====================================================================================
# =====================================================================================
# Function: install_drivers_in_container
# Description: Installs the NVIDIA driver and CUDA Toolkit inside the LXC container.
#              It downloads the NVIDIA runfile, executes it, and then installs
#              the CUDA Toolkit via apt.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if any installation step fails.
# =====================================================================================
install_drivers_in_container() {
    log_info "Starting NVIDIA driver and CUDA installation in CTID: $CTID"

    # --- Pre-flight Check ---
    log_info "Performing pre-flight check for NVIDIA devices in CTID: $CTID"
    if ! wait_for_nvidia_device "$CTID"; then
        log_fatal "Pre-flight check failed: NVIDIA device not found in container."
    fi
    log_info "Pre-flight check passed. NVIDIA device found."

    # --- Configuration Loading ---
    local nvidia_runfile_url
    nvidia_runfile_url=$(jq -r '.nvidia_runfile_url' "$LXC_CONFIG_FILE")
    local nvidia_driver_version
    nvidia_driver_version=$(jq -r '.nvidia_driver_version' "$LXC_CONFIG_FILE")
    local cuda_version
    cuda_version=$(jq -r '.nvidia_driver.cuda_version' "$HYPERVISOR_CONFIG_FILE" | tr '.' '-')
    local cache_dir="/usr/local/phoenix_hypervisor/cache"

    if [ -z "$nvidia_runfile_url" ] || [ -z "$nvidia_driver_version" ]; then
        log_fatal "NVIDIA runfile URL or driver version is not defined in the configuration."
    fi
    log_info "Targeting NVIDIA driver version: $nvidia_driver_version"

    # --- Prerequisite Installation ---
    log_info "Installing prerequisites (wget, build-essential, curl) in container..."
    pct_exec "$CTID" apt-get update
    pct_exec "$CTID" apt-get install -y wget build-essential curl

    # --- Runfile Caching and Transfer ---
    log_info "Checking for cached NVIDIA runfile..."
    local runfile_name
    runfile_name=$(basename "$nvidia_runfile_url")
    local host_runfile_path="${cache_dir}/${runfile_name}"

    if [ ! -f "$host_runfile_path" ]; then
        log_warn "NVIDIA runfile not found in cache. Downloading..."
        if ! wget -O "$host_runfile_path" "$nvidia_runfile_url"; then
            log_fatal "Failed to download NVIDIA runfile from $nvidia_runfile_url."
        fi
        log_info "Download complete. Runfile cached at $host_runfile_path."
    else
        log_info "NVIDIA runfile found in cache: $host_runfile_path"
    fi

    local container_runfile_path="/tmp/$runfile_name"
    log_info "Pushing runfile to container at $container_runfile_path..."
    if ! run_pct_push "$CTID" "$host_runfile_path" "$container_runfile_path"; then
        log_fatal "Failed to push NVIDIA driver to container. Aborting installation."
    fi

    # --- Driver Installation ---
    log_info "Making runfile executable and starting installation..."
    if ! pct_exec "$CTID" chmod +x "$container_runfile_path"; then
        log_fatal "Failed to make runfile executable in CTID $CTID."
    fi

    if ! pct_exec "$CTID" "$container_runfile_path" --silent --no-kernel-module --no-x-check --no-nouveau-check --no-nvidia-modprobe; then
        log_fatal "NVIDIA driver installation from runfile failed."
    fi
    log_info "NVIDIA driver installation complete."

    # --- Cleanup ---
    log_info "Cleaning up runfile from container..."
    pct_exec "$CTID" rm "$container_runfile_path"

    # --- CUDA Toolkit Installation ---
    log_info "Configuring NVIDIA CUDA repository..."
    ensure_nvidia_repo_is_configured "$CTID"
    log_info "Installing CUDA Toolkit version ${cuda_version}..."
    if ! pct_exec "$CTID" apt-get install -y "cuda-toolkit-${cuda_version}"; then
        log_fatal "Failed to install CUDA Toolkit."
    fi

    log_info "NVIDIA driver and CUDA installation process finished for CTID $CTID."
}

# =====================================================================================
# Function: main
# Description: Main entry point for the NVIDIA feature script.
# =====================================================================================
# =====================================================================================
# Function: main
# Description: Main entry point for the NVIDIA feature script.
#              It orchestrates the host-level GPU passthrough configuration,
#              driver and CUDA Toolkit installation inside the container, and
#              final verification.
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   Exits with status 0 on successful completion.
# =====================================================================================
main() {
    parse_arguments "$@"

    # --- Idempotency Check ---
    if is_feature_installed "$CTID" "nvidia"; then
        log_info "NVIDIA feature already installed on CTID $CTID. Skipping installation."
        exit_script 0
    fi
    # --- End Idempotency Check ---

    configure_host_gpu_passthrough # Configure GPU passthrough on the Proxmox host
    install_drivers_in_container # Install NVIDIA drivers and CUDA Toolkit inside the container
    exit_script 0 # Exit successfully
}

main "$@"