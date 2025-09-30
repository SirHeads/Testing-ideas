#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_nvidia.sh
# Description: This script is a critical modular feature installer that enables NVIDIA GPU acceleration
#              within an LXC container. It operates in two distinct phases, adhering to the "Host-Kernel,
#              Container-Userspace" architectural principle. First, it runs on the Proxmox host to
#              modify the container's configuration file, enabling GPU passthrough by mapping device
#              nodes and setting cgroup permissions. Second, it executes commands inside the container
#              to install the matching NVIDIA user-space drivers and the CUDA Toolkit. A key aspect of
#              this process is installing the driver from the `.run` file with the `--no-kernel-module`
#              flag, ensuring the container uses the host's kernel driver while having its own user-space
#              libraries. This script is idempotent and is called by the phoenix_orchestrator.sh when
#              "nvidia" is present in a container's `features` array in `phoenix_lxc_configs.json`.
#
# Dependencies:
#   - The Proxmox host must have the NVIDIA kernel driver correctly installed and loaded.
#   - phoenix_hypervisor_common_utils.sh: For shared functions.
#   - `jq` for parsing configuration files.
#   - An active internet connection in the container for downloading the driver and CUDA toolkit.
#
# Inputs:
#   - $1 (CTID): The unique Container ID of the target LXC container.
#   - `phoenix_lxc_configs.json`: Reads the `.gpu_assignment` and `.nvidia_runfile_url` for the specified CTID.
#
# Outputs:
#   - Modifies the container's configuration file on the host (`/etc/pve/lxc/<CTID>.conf`).
#   - Installs NVIDIA user-space drivers and CUDA Toolkit inside the container.
#   - Restarts the container to apply hardware configuration changes.
#   - Logs detailed progress to stdout and the main log file.
#   - Returns exit code 0 on success, non-zero on failure.
#
# Version: 1.1.0
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
# Description: Validates and parses the command-line arguments to ensure the script
#              receives the necessary Container ID (CTID).
# Arguments:
#   $1 - The Container ID (CTID) for the LXC container.
# Globals:
#   - CTID: Sets the global CTID variable for use in subsequent functions.
# Returns:
#   - None. Exits with status 2 if the CTID is not provided.
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        log_error "This script requires the LXC Container ID to install the NVIDIA feature."
        exit_script 2
    fi
    CTID="$1"
    log_info "Executing NVIDIA modular feature for CTID: $CTID"
}

# =====================================================================================
# Function: configure_host_gpu_passthrough
# Description: Modifies the LXC container's configuration file on the Proxmox host to
#              bind-mount the necessary NVIDIA devices.
# =====================================================================================
# =====================================================================================
# Function: configure_host_gpu_passthrough
# Description: This function performs the host-side operations required for GPU passthrough.
#              It reads the container's GPU assignment from the configuration and dynamically
#              adds the necessary `lxc.cgroup2.devices.allow` and `lxc.mount.entry` lines
#              to the container's `.conf` file. These lines grant the container permission
#              to access the GPU device nodes and then bind-mount them into the container's
#              filesystem. If any changes are made, the container is restarted to apply them.
# Arguments:
#   None (uses global CTID).
# Returns:
#   - None. Exits if the GPU assignment is missing or the config file is not found.
#   - Triggers a container restart if configuration changes are made.
# =====================================================================================
configure_host_gpu_passthrough() {
    log_info "Phase 1: Configuring host-side GPU passthrough for CTID: $CTID"
    local lxc_conf_file="/etc/pve/lxc/${CTID}.conf"
    local gpu_assignment
    local changes_made=false

    # Retrieve the GPU assignment (e.g., "0" or "0,1") from the main JSON configuration.
    gpu_assignment=$(jq_get_value "$CTID" ".gpu_assignment")
    if [ -z "$gpu_assignment" ] || [ "$gpu_assignment" == "none" ]; then
        log_info "No GPU assignment found for CTID $CTID in configuration. Skipping NVIDIA feature."
        exit_script 0
    fi

    if [ ! -f "$lxc_conf_file" ]; then
        log_fatal "LXC config file not found at $lxc_conf_file. Cannot configure GPU passthrough."
    fi

    # These entries grant the container access to the NVIDIA character devices.
    # Major number 195 is for NVIDIA devices, 243 for NVIDIA UVM.
    local cgroup_entries=(
        "lxc.cgroup2.devices.allow: c 195:* rwm"
        "lxc.cgroup2.devices.allow: c 243:* rwm"
    )
    local mount_entries=()

    # These are the standard control devices required for the NVIDIA driver to function.
    local standard_devices=("/dev/nvidiactl" "/dev/nvidia-uvm" "/dev/nvidia-uvm-tools")
    for device in "${standard_devices[@]}"; do
        if [ -e "$device" ]; then
            mount_entries+=("lxc.mount.entry: $device ${device#/} none bind,optional,create=file")
        else
            log_warn "Standard NVIDIA device $device not found on host. This may cause issues."
        fi
    done

    # Process the specific GPU devices assigned to this container.
    IFS=',' read -ra gpus <<< "$gpu_assignment"
    for gpu_idx in "${gpus[@]}"; do
        local nvidia_device="/dev/nvidia${gpu_idx}"
        if [ -e "$nvidia_device" ]; then
            mount_entries+=("lxc.mount.entry: $nvidia_device ${nvidia_device#/} none bind,optional,create=file")
        else
            log_warn "Assigned GPU device $nvidia_device not found on host. Passthrough for this GPU will fail."
        fi
    done

    # Idempotently add the required configuration lines to the container's config file.
    for entry in "${mount_entries[@]}" "${cgroup_entries[@]}"; do
        if ! grep -qF "$entry" "$lxc_conf_file"; then
            log_info "Adding entry to $lxc_conf_file: $entry"
            echo "$entry" >> "$lxc_conf_file"
            changes_made=true
        else
            log_info "Entry already exists, skipping: $entry"
        fi
    done

    log_info "Host GPU passthrough configuration complete for CTID $CTID."
    # A container restart is mandatory for changes to the .conf file to take effect.
    if [ "$changes_made" = true ]; then
        log_info "Restarting container CTID $CTID to apply new hardware passthrough settings..."
        run_pct_command stop "$CTID"
        run_pct_command start "$CTID"
        log_info "Container CTID $CTID restarted. Waiting for device to appear..."
        wait_for_nvidia_device "$CTID"
    else
        log_info "No changes made to container configuration. Ensuring container is running."
        run_pct_command start "$CTID" --force # Ensure the container is running for the next phase.
    fi
}

# =====================================================================================
# Function: wait_for_nvidia_device
# Description: Waits for the NVIDIA device node to appear in the container.
# =====================================================================================
wait_for_nvidia_device() {
    local ctid="$1"
    local device_path="/dev/nvidia0" # We only need to check for the first GPU device.
    local timeout=30
    local interval=2
    local elapsed_time=0

    log_info "Waiting up to ${timeout}s for NVIDIA device '$device_path' to become available in CTID $ctid..."

    # This loop prevents a race condition where the script tries to install drivers
    # before the kernel has made the passed-through device available inside the container.
    while [ $elapsed_time -lt $timeout ]; do
        # `pct exec` is used to run the `test -e` command inside the container.
        if pct exec "$ctid" -- test -e "$device_path"; then
            log_success "NVIDIA device found in CTID $ctid. Proceeding with installation."
            return 0
        fi
        sleep $interval
        elapsed_time=$((elapsed_time + interval))
    done

    log_error "Timeout reached. NVIDIA device '$device_path' not found in CTID $ctid after ${timeout} seconds."
    log_info "This usually indicates a problem with the host-side passthrough configuration in the .conf file."
    log_info "Contents of /dev/ in CTID $ctid:"
    pct exec "$ctid" -- ls -la /dev/
    log_fatal "Aborting NVIDIA feature installation due to missing device."
}

# =====================================================================================
# Function: install_drivers_in_container
# Description: Installs the NVIDIA driver and CUDA toolkit inside the container.
# =====================================================================================
install_drivers_in_container() {
    log_info "Phase 2: Starting NVIDIA user-space driver and CUDA installation in CTID: $CTID"

    # --- Idempotency Check ---
    # If nvidia-smi is already available, we can assume the installation is complete.
    if is_command_available "$CTID" "nvidia-smi"; then
        log_info "NVIDIA user-space driver (nvidia-smi) already found in CTID $CTID. Skipping installation."
        return 0
    fi

    # --- Configuration Loading ---
    local nvidia_runfile_url
    nvidia_runfile_url=$(jq_get_value "$CTID" ".nvidia_runfile_url")
    if [ -z "$nvidia_runfile_url" ] || [ "$nvidia_runfile_url" == "null" ]; then
        log_fatal "NVIDIA runfile URL is not defined in the configuration for CTID $CTID."
    fi

    # --- Prerequisite Installation ---
    log_info "Installing prerequisites (wget, build-essential, etc.) in container..."
    pct_exec "$CTID" -- apt-get update
    pct_exec "$CTID" -- apt-get install -y wget build-essential pkg-config libglvnd-dev curl gnupg

    # --- Driver Installation from .run file ---
    # This is the core of the container-side setup. We use the same .run file as the host
    # to ensure perfect version alignment between the host kernel module and the container's user-space tools.
    local runfile_name
    runfile_name=$(basename "$nvidia_runfile_url")
    local container_runfile_path="/tmp/${runfile_name}"

    log_info "Downloading NVIDIA runfile from $nvidia_runfile_url and pushing to container..."
    wget -qO "/tmp/${runfile_name}" "$nvidia_runfile_url"
    run_pct_push "$CTID" "/tmp/${runfile_name}" "$container_runfile_path"
    rm "/tmp/${runfile_name}" # Clean up the temporary file on the host.

    log_info "Executing NVIDIA runfile installer inside the container..."
    # The --no-kernel-module flag is CRITICAL. It tells the installer to only install user-space
    # components and not to touch the kernel, which is managed by the Proxmox host.
    local install_command="bash ${container_runfile_path} --silent --no-kernel-module --no-x-check --no-nouveau-check --no-nvidia-modprobe --no-dkms"
    pct_exec "$CTID" -- chmod +x "$container_runfile_path"
    if ! pct_exec "$CTID" -- $install_command; then
        log_fatal "NVIDIA driver installation from runfile failed inside CTID $CTID."
    fi
    pct_exec "$CTID" -- rm "$container_runfile_path" # Clean up the runfile inside the container.

    # --- CUDA Toolkit Installation ---
    # The CUDA toolkit provides the compilers (nvcc) and libraries needed for GPU-accelerated applications.
    ensure_nvidia_repo_is_configured "$CTID"
    log_info "Installing CUDA Toolkit from NVIDIA repository..."
    pct_exec "$CTID" -- apt-get update
    if ! pct_exec "$CTID" -- apt-get install -y cuda-toolkit-12-8; then
        log_fatal "Failed to install CUDA Toolkit in CTID $CTID."
    fi

    # --- Final Verification ---
    # Running these commands inside the container confirms that everything is working as expected.
    log_info "Final verification of NVIDIA components inside CTID $CTID..."
    if ! pct_exec "$CTID" -- nvidia-smi; then
        log_fatal "Final verification failed: 'nvidia-smi' command failed in CTID $CTID."
    fi
    if ! pct_exec "$CTID" -- /usr/local/cuda/bin/nvcc --version; then
        log_fatal "Final verification failed: 'nvcc' command not found or failed in CTID $CTID."
    fi

    log_success "NVIDIA user-space driver and CUDA installation process finished for CTID $CTID."
}

get_os_version_from_config() {
    local current_ctid="$1"
    local template_file
    local os_version

    while true; do
        template_file=$(jq_get_value "$current_ctid" ".template")
        if [ -n "$template_file" ] && [ "$template_file" != "null" ]; then
            os_version=$(echo "$template_file" | grep -oP 'ubuntu-\K[0-9]{2}\.[0-9]{2}')
            if [ -n "$os_version" ]; then
                echo "$os_version" | tr -d '.'
                return 0
            fi
        fi

        current_ctid=$(jq_get_value "$current_ctid" ".clone_from_ctid")
        if [ -z "$current_ctid" ] || [ "$current_ctid" == "null" ]; then
            log_error "Could not determine OS version for CTID $1. No template file found in hierarchy."
            return 1
        fi
    done
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

    # This function handles all operations that need to be performed on the Proxmox host itself,
    # primarily editing the container's configuration file and restarting it.
    configure_host_gpu_passthrough

    # This function handles all operations performed inside the container, namely the installation
    # of the user-space drivers and the CUDA toolkit.
    install_drivers_in_container

    log_info "Successfully completed NVIDIA feature for CTID $CTID."
    exit_script 0
}

main "$@"