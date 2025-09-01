#!/bin/bash
#
# File: feature_install_nvidia.sh
# Description: This feature script automates the configuration of NVIDIA GPU passthrough
#              and driver installation within a Proxmox LXC container. It is designed to be
#              called by the main orchestrator and is fully idempotent.
# Version: 1.0.0
# Author: Roo (AI Engineer)

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Source common utilities ---
source "$(dirname "$0")/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""

# =====================================================================================
# Function: parse_arguments
# Description: Parses the CTID from command-line arguments.
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Executing NVIDIA feature for CTID: $CTID"
}

# =====================================================================================
# Function: configure_host_gpu_passthrough
# Description: Modifies the LXC container's configuration file on the Proxmox host to
#              bind-mount the necessary NVIDIA devices.
# =====================================================================================
configure_host_gpu_passthrough() {
    log_info "Configuring host GPU passthrough for container CTID: $CTID"
    local lxc_conf_file="/etc/pve/lxc/${CTID}.conf"
    local gpu_assignment

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
        "lxc.cgroup2.devices.allow: c 195:* rwm" # NVIDIA devices
        "lxc.cgroup2.devices.allow: c 243:* rwm" # NVIDIA UVM devices
    )

    # Add standard devices
    local standard_devices=("/dev/nvidiactl" "/dev/nvidia-uvm" "/dev/nvidia-uvm-tools")
    for device in "${standard_devices[@]}"; do
        if [ -e "$device" ]; then
            mount_entries+=("lxc.mount.entry: $device ${device#/} none bind,optional,create=file")
        else
            log_warn "Standard NVIDIA device $device not found on host. Skipping."
        fi
    done

    # Add assigned GPU devices
    IFS=',' read -ra gpus <<< "$gpu_assignment"
    for gpu_idx in "${gpus[@]}"; do
        local nvidia_device="/dev/nvidia${gpu_idx}"
        if [ -e "$nvidia_device" ]; then
            mount_entries+=("lxc.mount.entry: $nvidia_device ${nvidia_device#/} none bind,optional,create=file")
        else
            log_warn "Assigned GPU device $nvidia_device not found on host. Skipping."
        fi
    done

    # Apply entries to the config file
    for entry in "${mount_entries[@]}" "${cgroup_entries[@]}"; do
        if ! grep -qF "$entry" "$lxc_conf_file"; then
            log_info "Adding entry to $lxc_conf_file: $entry"
            echo "$entry" >> "$lxc_conf_file"
        else
            log_info "Entry already exists in $lxc_conf_file: $entry"
        fi
    done

    log_info "Host GPU passthrough configuration complete for CTID $CTID."
    # --- Restart the container to apply the new hardware settings ---
    log_info "Restarting container CTID $CTID to apply GPU passthrough settings..."
    run_pct_command stop "$CTID"
    run_pct_command start "$CTID"
    log_info "Container CTID $CTID restarted successfully."
}

# =====================================================================================
# Function: install_drivers_in_container
# Description: Installs the NVIDIA driver and CUDA toolkit inside the container.
# =====================================================================================
install_drivers_in_container() {
    log_info "Starting NVIDIA driver and CUDA installation in CTID: $CTID"

    # The NVIDIA runfile installer is idempotent and will handle cases where
    # the driver is already installed. The final verification is done by the
    # verify_installation function.

    local nvidia_runfile_url
    nvidia_runfile_url=$(jq -r '.nvidia_runfile_url' "$LXC_CONFIG_FILE")

    # Install prerequisites
    pct_exec "$CTID" apt-get update
    pct_exec "$CTID" apt-get install -y wget build-essential

    # Download and install the runfile
    local runfile_name
    runfile_name=$(basename "$nvidia_runfile_url")
    local runfile_path="/tmp/$runfile_name"

    log_info "Downloading NVIDIA driver runfile to $runfile_path in CTID $CTID..."
    pct_exec "$CTID" wget -q "$nvidia_runfile_url" -O "$runfile_path"

    log_info "Making runfile executable..."
    pct_exec "$CTID" chmod +x "$runfile_path"

    log_info "Executing NVIDIA driver runfile installation..."
    pct_exec "$CTID" "$runfile_path" --silent --no-kernel-module --no-x-check --no-nouveau-check

    # Clean up
    pct_exec "$CTID" rm "$runfile_path"

    # --- Ensure NVIDIA CUDA Repository is configured ---
    ensure_nvidia_repo_is_configured "$CTID"

    # --- Install CUDA Toolkit ---
    log_info "Installing CUDA Toolkit in CTID $CTID..."
    pct_exec "$CTID" apt-get install -y cuda-toolkit-12-8

    log_info "NVIDIA driver and CUDA installation complete for CTID $CTID."
}

# =====================================================================================
# Function: verify_installation
# Description: Verifies the NVIDIA installation by running nvidia-smi inside the container.
# =====================================================================================
verify_installation() {
    log_info "Verifying NVIDIA installation in CTID: $CTID"
    if ! pct_exec "$CTID" nvidia-smi; then
        log_fatal "NVIDIA verification failed. 'nvidia-smi' command failed in CTID $CTID."
    fi
    log_info "NVIDIA installation verified successfully in CTID $CTID."
}


# =====================================================================================
# Function: main
# Description: Main entry point for the NVIDIA feature script.
# =====================================================================================
main() {
    parse_arguments "$@"
    configure_host_gpu_passthrough
    install_drivers_in_container
    verify_installation
    exit_script 0
}

main "$@"