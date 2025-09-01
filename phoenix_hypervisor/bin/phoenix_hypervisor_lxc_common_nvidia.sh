#!/bin/bash
set -x
source "$(dirname "$0")/phoenix_hypervisor_common_utils.sh"

log_debug "LANG is set to: $LANG"
log_debug "LC_ALL is set to: $LC_ALL"

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
# ./phoenix_hypervisor_lxc_common_nvidia.sh <CTID>
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
# Sourced from phoenix_hypervisor_common_utils.sh

# --- Logging Functions ---
# Sourced from phoenix_hypervisor_common_utils.sh

# --- Exit Function ---
# Sourced from phoenix_hypervisor_common_utils.sh

log_info "IMPORTANT: Ensure 'nvidia-persistenced' service is running on the Proxmox host for proper GPU device access within LXC containers."

# --- Script Variables ---
CTID=""
GPU_ASSIGNMENT=""
NVIDIA_DRIVER_VERSION=""
NVIDIA_REPO_URL=""
NVIDIA_RUNFILE_URL=""

### Function: parse_arguments
# Purpose: Parses command-line arguments to extract the Container ID (CTID) and NVIDIA-related variables.
# Content:
# *   Checks if exactly five arguments are provided.
# *   If not, logs a usage error and exits with code 2.
# *   Assigns the arguments to the respective variables.
# *   Logs the successfully received arguments.
parse_arguments() {
    if [ "$#" -ne 5 ]; then
        log_error "Usage: $0 <CTID> <GPU_ASSIGNMENT> <NVIDIA_DRIVER_VERSION> <NVIDIA_REPO_URL> <NVIDIA_RUNFILE_URL>"
        exit_script 2
    fi
    CTID="$1"
    GPU_ASSIGNMENT="$2"
    NVIDIA_DRIVER_VERSION="$3"
    NVIDIA_REPO_URL="$4"
    NVIDIA_RUNFILE_URL="$5"
    log_info "Received CTID: $CTID, GPU_ASSIGNMENT: $GPU_ASSIGNMENT, NVIDIA_DRIVER_VERSION: $NVIDIA_DRIVER_VERSION, NVIDIA_REPO_URL: $NVIDIA_REPO_URL, NVIDIA_RUNFILE_URL: $NVIDIA_RUNFILE_URL"
}

### Function: validate_inputs
# Purpose: Validates all necessary inputs, including the CTID and required arguments,
#          to ensure the script can proceed with configuration.
# Content:
# *   Verifies that `CTID` is a positive integer; otherwise, logs a fatal error and exits.
# *   Logs a success message if all input validations pass.
validate_inputs() {
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_error "FATAL: Invalid CTID '$CTID'. Must be a positive integer."
        exit_script 2
    fi
    if [ -z "$GPU_ASSIGNMENT" ]; then
        log_error "FATAL: GPU_ASSIGNMENT is not set."
        exit_script 2
    fi
    if [ -z "$NVIDIA_DRIVER_VERSION" ]; then
        log_error "FATAL: NVIDIA_DRIVER_VERSION is not set."
        exit_script 2
    fi
    if [ -z "$NVIDIA_REPO_URL" ]; then
        log_error "FATAL: NVIDIA_REPO_URL is not set."
        exit_script 2
    fi
    if [ -z "$NVIDIA_RUNFILE_URL" ]; then
        log_info "NVIDIA_RUNFILE_URL is not set. This is optional and may be used for runfile installations."
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

    local mount_entries=()
    local cgroup_entries=()
    local idmap_entries=()

    # Common devices
    local common_devices=(
        "/dev/dri/card0"
        "/dev/dri/renderD128"
        "/dev/nvidiactl"
        "/dev/nvidia-uvm"
        "/dev/nvidia-uvm-tools"
        "/dev/nvidia-caps/nvidia-cap1"
        "/dev/nvidia-caps/nvidia-cap2"
    )

    # Add common devices if any GPU is assigned
    if [ "$GPU_ASSIGNMENT" != "none" ]; then
        for device in "${common_devices[@]}"; do
            if [ -e "$device" ]; then
                local device_type="file"
                if [ -d "$device" ]; then
                    device_type="dir"
                fi
                mount_entries+=("lxc.mount.entry: $device ${device#/} none bind,optional,create=$device_type")
                log_info "Device $device exists on host. Adding mount entry."
            else
                log_warn "Device $device does not exist on host. Skipping mount entry."
            fi
        done

        # Add GPU specific devices
        IFS=',' read -ra GPUS <<< "$GPU_ASSIGNMENT"
        for gpu_idx in "${GPUS[@]}"; do
            local nvidia_device="/dev/nvidia${gpu_idx}"
            if [ -e "$nvidia_device" ]; then
                mount_entries+=("lxc.mount.entry: $nvidia_device ${nvidia_device#/} none bind,optional,create=file")
                log_info "Device $nvidia_device exists on host. Adding mount entry."
            else
                log_warn "Device $nvidia_device does not exist on host. Skipping mount entry."
            fi
        done

        # Add cgroup device allow rules for NVIDIA devices
        cgroup_entries+=(
            "lxc.cgroup2.devices.allow: c 195:* rwm" # NVIDIA devices
            "lxc.cgroup2.devices.allow: c 243:* rwm" # NVIDIA UVM devices
            "lxc.cgroup2.devices.allow: c 226:* rwm" # DRI devices (for /dev/dri/card0, renderD128)
        )

        # Add GID mapping for unprivileged containers
        # Assuming a common mapping for unprivileged containers. Adjust if specific mapping is required.
        idmap_entries+=(
            "lxc.idmap: g 0 100000 100000"
            "lxc.idmap: g 100000 0 1" # Map host GID 0 (root) to container GID 100000
            "lxc.idmap: g 100001 100001 65535" # Map host GID 100001 to container GID 100001
        )
    else
        log_info "GPU_ASSIGNMENT is 'none'. No GPU devices to configure."
    fi

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

    # Apply idmap entries
    for entry in "${idmap_entries[@]}"; do
        if ! grep -qF "$entry" "$lxc_conf_file"; then
            log_info "Adding idmap entry: $entry"
            echo "$entry" >> "$lxc_conf_file"
            if [ $? -ne 0 ]; then
                log_error "FATAL: Failed to add idmap entry '$entry' for CTID $CTID."
                exit_script 4
            fi
        else
            log_info "Idmap entry '$entry' already exists for CTID $CTID. Skipping."
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
    local expected_idmap_entries=(
        "lxc.idmap: g 0 100000 100000"
        "lxc.idmap: g 100000 0 1"
        "lxc.idmap: g 100001 100001 65535"
    )

    if [ "$GPU_ASSIGNMENT" != "none" ]; then
        # Dynamically generate expected mount entries based on GPU_ASSIGNMENT
        local dynamic_mount_entries=()
        local common_devices=(
            "/dev/dri/card0"
            "/dev/dri/renderD128"
            "/dev/nvidiactl"
            "/dev/nvidia-uvm"
            "/dev/nvidia-uvm-tools"
            "/dev/nvidia-caps/nvidia-cap1"
            "/dev/nvidia-caps/nvidia-cap2"
        )
        for device in "${common_devices[@]}"; do
            local device_type="file"
            if [ -d "$device" ]; then
                device_type="dir"
            fi
            dynamic_mount_entries+=("lxc.mount.entry: $device ${device#/} none bind,optional,create=$device_type")
        done

        IFS=',' read -ra GPUS <<< "$GPU_ASSIGNMENT"
        for gpu_idx in "${GPUS[@]}"; do
            local nvidia_device="/dev/nvidia${gpu_idx}"
            dynamic_mount_entries+=("lxc.mount.entry: $nvidia_device ${nvidia_device#/} none bind,optional,create=file")
        done

        entries_to_check+=("${dynamic_mount_entries[@]}")
        entries_to_check+=("${expected_cgroup_entries[@]}")
        entries_to_check+=("${expected_idmap_entries[@]}")
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

### Function: install_driver_from_runfile
# Purpose: Downloads and installs the NVIDIA driver using the .run file inside the LXC container.
# Content:
# *   Ensures basic tools like curl are available inside the container.
# *   Downloads the .run file from NVIDIA_RUNFILE_URL.
# *   Makes the .run file executable.
# *   Executes the .run file with --silent --driver-only flags.
# *   Includes an idempotency check to verify if the correct NVIDIA driver version is already installed.
install_driver_from_runfile() {
    log_info "Starting NVIDIA driver installation from .run file inside container CTID: $CTID"

    # Idempotency check: Verify if the correct NVIDIA driver version is already installed
    log_info "[CTID $CTID] Checking for existing NVIDIA driver version..."
    local installed_driver_version
    installed_driver_version=$(pct exec "$CTID" -- bash -c "modinfo nvidia | grep -oP 'Version: \K.*' || true" 2>/dev/null)

    if [ -n "$installed_driver_version" ] && [[ "$installed_driver_version" == *"$NVIDIA_DRIVER_VERSION"* ]]; then
        log_info "[CTID $CTID] NVIDIA driver version $NVIDIA_DRIVER_VERSION already installed. Skipping .run file installation."
        return 0
    else
        log_info "[CTID $CTID] NVIDIA driver version $NVIDIA_DRIVER_VERSION not found or incorrect version ($installed_driver_version). Proceeding with .run file installation."
    fi

    # Ensure basic tools like curl are available inside the container
    log_info "[CTID $CTID] Installing curl and other prerequisites for .run file download..."
    if ! pct exec "$CTID" -- apt-get update; then
        log_error "FATAL: [CTID $CTID] Failed to apt-get update inside container for .run file prerequisites."
        exit_script 5
    fi
    if ! pct exec "$CTID" -- apt-get install -y curl wget; then
        log_error "FATAL: [CTID $CTID] Failed to install curl or wget inside container for .run file download."
        exit_script 5
    fi

    local runfile_name=$(basename "$NVIDIA_RUNFILE_URL")
    local runfile_path="/tmp/$runfile_name"

    log_info "[CTID $CTID] Downloading NVIDIA driver .run file from $NVIDIA_RUNFILE_URL to $runfile_path..."
    if ! pct exec "$CTID" -- wget -q "$NVIDIA_RUNFILE_URL" -O "$runfile_path"; then
        log_error "FATAL: [CTID $CTID] Failed to download NVIDIA driver .run file from $NVIDIA_RUNFILE_URL."
        exit_script 5
    fi

    log_info "[CTID $CTID] Making NVIDIA driver .run file executable..."
    if ! pct exec "$CTID" -- chmod +x "$runfile_path"; then
        log_error "FATAL: [CTID $CTID] Failed to make .run file executable."
        exit_script 5
    fi

    log_info "[CTID $CTID] Executing NVIDIA driver .run file with --silent --driver-only..."
    if ! pct exec "$CTID" -- "$runfile_path" --silent --driver-only --no-kernel-module-source; then
        log_error "FATAL: [CTID $CTID] NVIDIA driver .run file installation failed."
        exit_script 5
    fi
    
    # Clean up the runfile
    pct exec "$CTID" -- rm "$runfile_path"

    log_info "NVIDIA driver installation from .run file inside container CTID: $CTID completed."
}

### Function: install_nvidia_drivers_in_container
# Purpose: Installs NVIDIA drivers (via .run file) and CUDA toolkit (via apt) inside the LXC container.
# Content:
# *   Calls install_driver_from_runfile to install the NVIDIA driver.
# *   Ensures basic tools like curl are available inside the container.
# *   Adds NVIDIA CUDA repository.
# *   Installs NVIDIA CUDA toolkit and related LLM packages.
# *   Runs ldconfig to update shared library cache.
install_nvidia_drivers_in_container() {
    log_info "Starting hybrid NVIDIA driver (.run) and CUDA toolkit (apt) installation inside container CTID: $CTID"

    # Install NVIDIA driver from .run file first
    install_driver_from_runfile
    local driver_install_status=$?
    if [ "$driver_install_status" -ne 0 ]; then
        log_error "FATAL: [CTID $CTID] NVIDIA driver installation from .run file failed with exit code $driver_install_status."
        exit_script 5
    fi

    # Ensure basic tools for apt are available inside the container
    log_info "[CTID $CTID] Installing apt prerequisites..."
    if ! pct exec "$CTID" -- apt-get update; then
        log_error "FATAL: [CTID $CTID] Failed to apt-get update inside container."
        exit_script 5
    fi
    if ! pct exec "$CTID" -- apt-get install -y curl gnupg software-properties-common; then
        log_error "FATAL: [CTID $CTID] Failed to install curl, gnupg, software-properties-common inside container."
        exit_script 5
    fi

    # Add NVIDIA CUDA repository
    log_info "[CTID $CTID] Adding NVIDIA CUDA repository from $NVIDIA_REPO_URL..."
    local CUDA_KEYRING_DEB="cuda-keyring_1.1-1_all.deb"
    local CUDA_KEYRING_URL="$NVIDIA_REPO_URL/$CUDA_KEYRING_DEB"
    log_info "[CTID $CTID] Downloading CUDA GPG keyring from $CUDA_KEYRING_URL..."
    if ! pct exec "$CTID" -- wget -q "$CUDA_KEYRING_URL" -O "/tmp/$CUDA_KEYRING_DEB"; then
        log_error "FATAL: [CTID $CTID] Failed to download CUDA GPG keyring package from $CUDA_KEYRING_URL."
        exit_script 5
    fi
    log_info "[CTID $CTID] Installing CUDA GPG keyring package..."
    if ! pct exec "$CTID" -- dpkg -i "/tmp/$CUDA_KEYRING_DEB"; then
        log_error "FATAL: [CTID $CTID] Failed to install CUDA GPG keyring package."
        exit_script 5
    fi
    pct exec "$CTID" -- rm "/tmp/$CUDA_KEYRING_DEB"
    if ! pct exec "$CTID" -- bash -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] $NVIDIA_REPO_URL/ /\" | tee /etc/apt/sources.list.d/cuda-\$(lsb_release -cs).list"; then
        log_error "FATAL: [CTID $CTID] Failed to add CUDA repository to sources.list.d."
        exit_script 5
    fi

    log_info "[CTID $CTID] Updating apt-get after adding NVIDIA repository..."
    if ! pct exec "$CTID" -- apt-get update; then
        log_error "FATAL: [CTID $CTID] Failed to apt-get update after adding NVIDIA repository."
        exit_script 5
    fi

    # Install CUDA toolkit and related LLM packages
    local cuda_toolkit_package="cuda-toolkit-12-8"
    local llm_packages="libcudnn8 libnccl2" # Add other relevant LLM packages here

    log_info "[CTID $CTID] Installing CUDA toolkit ($cuda_toolkit_package) and LLM packages ($llm_packages)..."
    if ! pct exec "$CTID" -- apt-get install -y "$cuda_toolkit_package" "$llm_packages"; then
        log_error "FATAL: [CTID $CTID] Failed to install CUDA toolkit and LLM packages."
        exit_script 5
    fi

    log_info "[CTID $CTID] Running ldconfig to update shared library cache..."
    if ! pct exec "$CTID" -- ldconfig; then
        log_warn "WARNING: [CTID $CTID] Failed to run ldconfig. This might affect library loading."
    fi

    log_info "Hybrid NVIDIA driver and CUDA toolkit installation inside container CTID: $CTID completed."
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
    install_nvidia_drivers_in_container
    exit_script 0
}

# Call the main function
main "$@"
