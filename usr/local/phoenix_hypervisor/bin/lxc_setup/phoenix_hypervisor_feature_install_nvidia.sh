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
    local lxc_conf_file="/etc/pve/lxc/${CTID}.conf" # Path to the LXC container's configuration file
    local gpu_assignment # Variable to store GPU assignment from config

    gpu_assignment=$(jq_get_value "$CTID" ".gpu_assignment") # Retrieve GPU assignment from config
    # If no GPU assignment is found, log and exit the script
    if [ -z "$gpu_assignment" ] || [ "$gpu_assignment" == "none" ]; then
        log_info "No GPU assignment found for CTID $CTID. Skipping NVIDIA feature."
        exit_script 0
    fi

    # Check if the LXC configuration file exists
    if [ ! -f "$lxc_conf_file" ]; then
        log_fatal "LXC config file not found at $lxc_conf_file."
    fi

    local mount_entries=() # Array to hold LXC mount entries
    local cgroup_entries=( # Array to hold LXC cgroup device allow entries
        "lxc.cgroup2.devices.allow: c 195:* rwm" # Allow access to NVIDIA devices
        "lxc.cgroup2.devices.allow: c 243:* rwm" # Allow access to NVIDIA UVM devices
    )

    # Add standard devices
    # Add standard NVIDIA devices to mount entries
    local standard_devices=("/dev/nvidiactl" "/dev/nvidia-uvm" "/dev/nvidia-uvm-tools")
    for device in "${standard_devices[@]}"; do
        if [ -e "$device" ]; then # Check if device exists on host
            mount_entries+=("lxc.mount.entry: $device ${device#/} none bind,optional,create=file") # Add mount entry
        else
            log_warn "Standard NVIDIA device $device not found on host. Skipping."
        fi
    done

    # Add assigned GPU devices
    # Add assigned GPU devices (e.g., /dev/nvidia0, /dev/nvidia1) to mount entries
    IFS=',' read -ra gpus <<< "$gpu_assignment" # Split gpu_assignment string by comma
    for gpu_idx in "${gpus[@]}"; do
        local nvidia_device="/dev/nvidia${gpu_idx}" # Construct device path
        if [ -e "$nvidia_device" ]; then # Check if device exists on host
            mount_entries+=("lxc.mount.entry: $nvidia_device ${nvidia_device#/} none bind,optional,create=file") # Add mount entry
        else
            log_warn "Assigned GPU device $nvidia_device not found on host. Skipping."
        fi
    done

    # Apply entries to the config file
    # Apply all mount and cgroup entries to the LXC config file
    for entry in "${mount_entries[@]}" "${cgroup_entries[@]}"; do
        if ! grep -qF "$entry" "$lxc_conf_file"; then # Check if entry already exists
            log_info "Adding entry to $lxc_conf_file: $entry"
            echo "$entry" >> "$lxc_conf_file" # Append entry to config file
        else
            log_info "Entry already exists in $lxc_conf_file: $entry"
        fi
    done

    log_info "Host GPU passthrough configuration complete for CTID $CTID."
    # Restart the container to apply the new hardware settings
    log_info "Restarting container CTID $CTID to apply GPU passthrough settings..."
    run_pct_command stop "$CTID" # Stop the container
    run_pct_command start "$CTID" # Start the container
    log_info "Container CTID $CTID restarted successfully."
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

    # Note: The NVIDIA runfile installer is idempotent and will handle cases where
    # the driver is already installed. Final verification is performed by `verify_installation`.

    local nvidia_runfile_url # URL for the NVIDIA driver runfile
    nvidia_runfile_url=$(jq -r '.nvidia_runfile_url' "$LXC_CONFIG_FILE") # Retrieve runfile URL from config

    # Install prerequisites
    # Install prerequisites inside the container
    pct_exec "$CTID" apt-get update # Update package lists
    pct_exec "$CTID" apt-get install -y wget build-essential # Install wget and build tools

    # Download and install the runfile
    local runfile_name # Name of the NVIDIA driver runfile
    runfile_name=$(basename "$nvidia_runfile_url") # Extract filename from URL
    local runfile_path="/tmp/$runfile_name" # Temporary path for the runfile

    log_info "Downloading NVIDIA driver runfile to $runfile_path in CTID $CTID..."
    log_info "Downloading NVIDIA driver runfile to $runfile_path in CTID $CTID..."
    pct_exec "$CTID" wget -q "$nvidia_runfile_url" -O "$runfile_path" # Download runfile

    log_info "Making runfile executable..."
    log_info "Making runfile executable..."
    pct_exec "$CTID" chmod +x "$runfile_path" # Make the runfile executable

    log_info "Executing NVIDIA driver runfile installation..."
    log_info "Executing NVIDIA driver runfile installation..."
    pct_exec "$CTID" "$runfile_path" --silent --no-kernel-module --no-x-check --no-nouveau-check # Execute runfile

    # Clean up
    # Clean up the downloaded runfile
    pct_exec "$CTID" rm "$runfile_path" # Remove runfile

    # --- Ensure NVIDIA CUDA Repository is configured ---
    # Ensure NVIDIA CUDA Repository is configured (from common_utils)
    ensure_nvidia_repo_is_configured "$CTID"

    # --- Install CUDA Toolkit ---
    # Install CUDA Toolkit
    log_info "Installing CUDA Toolkit in CTID $CTID..."
    pct_exec "$CTID" apt-get install -y cuda-toolkit-12-8 # Install CUDA Toolkit

    log_info "NVIDIA driver and CUDA installation complete for CTID $CTID."
}

# =====================================================================================
# Function: verify_installation
# Description: Verifies the NVIDIA installation by running nvidia-smi inside the container.
# =====================================================================================
# =====================================================================================
# Function: verify_installation
# Description: Verifies the NVIDIA driver and CUDA installation inside the container
#              by executing the `nvidia-smi` command.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if `nvidia-smi` command fails.
# =====================================================================================
verify_installation() {
    log_info "Verifying NVIDIA installation in CTID: $CTID"
    # Execute `nvidia-smi` inside the container to verify driver functionality
    if ! pct_exec "$CTID" nvidia-smi; then
        log_fatal "NVIDIA verification failed. 'nvidia-smi' command failed in CTID $CTID."
    fi
    log_info "NVIDIA installation verified successfully in CTID $CTID."
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
    parse_arguments "$@" # Parse command-line arguments
    configure_host_gpu_passthrough # Configure GPU passthrough on the Proxmox host
    install_drivers_in_container # Install NVIDIA drivers and CUDA Toolkit inside the container
    verify_installation # Verify the NVIDIA installation
    exit_script 0 # Exit successfully
}

main "$@"