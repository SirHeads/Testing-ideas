#!/bin/bash
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
# NVIDIA_DRIVER_VERSION="<driver_version_string>" \
# NVIDIA_REPO_URL="<nvidia_apt_repository_url>" \
# NVIDIA_RUNFILE_URL="<nvidia_driver_runfile_download_url>" \
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
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"

# --- Logging Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] phoenix_hypervisor_lxc_common_nvidia.sh: $*" | tee -a "$MAIN_LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] phoenix_hypervisor_lxc_common_nvidia.sh: $*" | tee -a "$MAIN_LOG_FILE" >&2
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

# --- Script Variables ---
CTID=""

### Function: parse_arguments
# Purpose: Parses command-line arguments to extract the Container ID (CTID).
# Content:
# *   Checks if exactly one argument is provided.
# *   If not, logs a usage error and exits with code 2.
# *   Assigns the first argument to the `CTID` variable.
# *   Logs the successfully received CTID.
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Received CTID: $CTID"
}

### Function: validate_inputs
# Purpose: Validates all necessary inputs, including the CTID and required environment variables,
#          to ensure the script can proceed with configuration.
# Content:
# *   Verifies that `CTID` is a positive integer; otherwise, logs a fatal error and exits.
# *   Checks if `GPU_ASSIGNMENT`, `NVIDIA_DRIVER_VERSION`, `NVIDIA_REPO_URL`, and `NVIDIA_RUNFILE_URL`
#     environment variables are set and not empty. If any are missing, logs a fatal error and exits.
# *   Logs a success message if all input validations pass.
validate_inputs() {
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_error "FATAL: Invalid CTID '$CTID'. Must be a positive integer."
        exit_script 2
    fi
    if [ -z "$GPU_ASSIGNMENT" ] || [ -z "$NVIDIA_DRIVER_VERSION" ] || [ -z "$NVIDIA_REPO_URL" ] || [ -z "$NVIDIA_RUNFILE_URL" ]; then
        log_error "FATAL: One or more required environment variables (GPU_ASSIGNMENT, NVIDIA_DRIVER_VERSION, NVIDIA_REPO_URL, NVIDIA_RUNFILE_URL) are not set."
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

    local standard_devices=("/dev/nvidiactl" "/dev/nvidia-uvm" "/dev/nvidia-uvm-tools" "/dev/nvidia-caps")
    local mount_entries=()

    if [ "$GPU_ASSIGNMENT" != "none" ]; then
        IFS=',' read -ra gpu_indices <<< "$GPU_ASSIGNMENT"
        for idx in "${gpu_indices[@]}"; do
            local device_path="/dev/nvidia${idx}"
            if [ -e "$device_path" ]; then
                mount_entries+=("lxc.mount.entry: ${device_path} ${device_path} none bind,optional,create=file 0 0")
            else
                log_error "WARNING: GPU device not found on host: $device_path"
            fi
        done
    fi

    for device in "${standard_devices[@]}"; do
        local create_type="file"
        if [ "$device" == "/dev/nvidia-caps" ]; then
            create_type="dir"
        fi

        if [ -e "$device" ]; then
            mount_entries+=("lxc.mount.entry: ${device} ${device} none bind,optional,create=${create_type} 0 0")
        else
            log_error "WARNING: Standard NVIDIA device not found on host: $device"
        fi
    done

    for entry in "${mount_entries[@]}"; do
        if ! grep -Fxq "$entry" "$lxc_conf_file"; then
            log_info "Appending to LXC config: $entry"
            echo "$entry" >> "$lxc_conf_file"
        else
            log_info "Entry already exists in LXC config: $entry"
        fi
    done
    log_info "Host GPU passthrough configuration complete."
}

### Function: install_nvidia_software_in_container
# Purpose: Installs the NVIDIA driver (using a `.run` file) and the CUDA toolkit/utilities
#          inside the specified LXC container using `pct exec` commands.
# Content:
# *   Defines the `RUNFILE_DEST_PATH` for the NVIDIA driver installer within the container.
# *   **Idempotency Check:**
#     *   Attempts to run `nvidia-smi --version` inside the container.
#     *   If the command succeeds and the version matches `NVIDIA_DRIVER_VERSION`, logs that
#         the driver is already installed and skips further installation steps.
# *   **Add NVIDIA Repository:**
#     *   Updates APT package lists.
#     *   Installs `software-properties-common` for `add-apt-repository`.
#     *   Adds the NVIDIA APT repository specified by `NVIDIA_REPO_URL` to the container's sources.
#     *   Updates APT package lists again to include the new repository.
# *   **Download NVIDIA Driver .run File:**
#     *   Downloads the NVIDIA driver `.run` file from `NVIDIA_RUNFILE_URL` to `RUNFILE_DEST_PATH`
#         inside the container using `curl`. Exits with an error if the download fails.
# *   **Install NVIDIA Driver (.run file):**
#     *   Makes the downloaded `.run` file executable.
#     *   Executes the `.run` file with `--no-kernel-module --silent` flags for a non-interactive
#         installation without building kernel modules (as these are handled by the host).
#     *   Exits with an error if the driver installation fails.
# *   **Install CUDA and Utilities (via apt):**
#     *   Extracts the major version from `NVIDIA_DRIVER_VERSION`.
#     *   Installs `cuda-drivers-<MAJOR_VERSION>` and `nvtop` via `apt-get`.
#     *   Exits with an error if the installation of CUDA components fails.
# *   **Verify Installation (inside Container):**
#     *   Executes `nvidia-smi` inside the container to verify the driver is functioning and
#         GPUs are recognized.
#     *   Exits with an error if `nvidia-smi` fails post-installation.
# *   Logs completion of NVIDIA software installation.
install_nvidia_software_in_container() {
    log_info "Installing NVIDIA software in container CTID: $CTID"
    local runfile_dest_path="/tmp/nvidia-driver-installer.run"

    if pct exec "$CTID" -- nvidia-smi --version | grep -q "$NVIDIA_DRIVER_VERSION"; then
        log_info "NVIDIA driver already installed and version matches. Skipping installation."
        return
    fi

    log_info "Adding NVIDIA repository inside the container..."
    pct exec "$CTID" -- apt-get update
    pct exec "$CTID" -- apt-get install -y software-properties-common
    pct exec "$CTID" -- add-apt-repository "deb $NVIDIA_REPO_URL $(lsb_release -cs) main"
    pct exec "$CTID" -- apt-get update

    log_info "Downloading NVIDIA driver .run file..."
    if ! pct exec "$CTID" -- curl -fL -o "$runfile_dest_path" "$NVIDIA_RUNFILE_URL"; then
        log_error "FATAL: Failed to download NVIDIA driver .run file."
        exit_script 5
    fi

    log_info "Installing NVIDIA driver..."
    pct exec "$CTID" -- chmod +x "$runfile_dest_path"
    if ! pct exec "$CTID" -- "$runfile_dest_path" --no-kernel-module --silent; then
        log_error "FATAL: Failed to install NVIDIA driver."
        exit_script 5
    fi

    log_info "Installing CUDA and utilities..."
    local major_version=$(echo "$NVIDIA_DRIVER_VERSION" | cut -d. -f1)
    if ! pct exec "$CTID" -- apt-get install -y "cuda-drivers-${major_version}" nvtop; then
        log_error "FATAL: Failed to install CUDA drivers and utilities."
        exit_script 5
    fi

    log_info "Verifying NVIDIA installation..."
    if ! pct exec "$CTID" -- nvidia-smi; then
        log_error "FATAL: nvidia-smi command failed after installation."
        exit_script 5
    fi
    log_info "NVIDIA software installation complete."
}

### Function: restart_container
# Purpose: Restarts the LXC container to ensure that newly applied device mounts
#          and installed NVIDIA software are properly activated and recognized.
# Content:
# *   Logs the intention to restart the container for configuration changes.
# *   Sets a `timeout` (60 seconds) and `interval` (3 seconds) for polling container status.
# *   **Stop Container:**
#     *   Attempts to stop the container using `pct stop "$CTID"`.
#     *   Exits with an error if the stop command fails to initiate.
# *   **Wait for Stopped State:**
#     *   Enters a loop, polling `pct status "$CTID"` until the container reports "stopped" or a timeout occurs.
#     *   Logs progress and exits with an error if the container does not stop within the `timeout`.
# *   **Start Container:**
#     *   Attempts to start the container using `pct start "$CTID"`.
#     *   Exits with an error if the start command fails to initiate.
# *   **Wait for Running State:**
#     *   Enters a loop, polling `pct status "$CTID"` until the container reports "running" or a timeout occurs.
#     *   Logs progress and exits with an error if the container does not start within the `timeout`.
# *   Logs successful completion of the container restart.
restart_container() {
    log_info "Restarting container CTID: $CTID to apply configuration changes."
    local timeout=60
    local interval=3
    local elapsed_time=0

    log_info "Attempting to stop container $CTID..."
    if ! pct stop "$CTID"; then
        log_error "FATAL: Failed to initiate stop for container $CTID."
        exit_script 6
    fi

    log_info "Waiting for container $CTID to stop (timeout: ${timeout}s, interval: ${interval}s)..."
    elapsed_time=0
    while [ "$elapsed_time" -lt "$timeout" ]; do
        if [ "$(pct status "$CTID" | awk '{print $2}')" == "stopped" ]; then
            log_info "Container $CTID successfully stopped."
            break
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    if [ "$elapsed_time" -ge "$timeout" ]; then
        log_error "FATAL: Container $CTID did not stop within the allotted time."
        exit_script 6
    fi

    log_info "Attempting to start container $CTID..."
    if ! pct start "$CTID"; then
        log_error "FATAL: Failed to initiate start for container $CTID."
        exit_script 6
    fi

    log_info "Waiting for container $CTID to start (timeout: ${timeout}s, interval: ${interval}s)..."
    elapsed_time=0
    while [ "$elapsed_time" -lt "$timeout" ]; do
        if [ "$(pct status "$CTID" | awk '{print $2}')" == "running" ]; then
            log_info "Container $CTID successfully started."
            break
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    if [ "$elapsed_time" -ge "$timeout" ]; then
        log_error "FATAL: Container $CTID did not start within the allotted time."
        exit_script 6
    fi

    log_info "Container $CTID restarted successfully."
}

### Function: main
# Purpose: Serves as the entry point for the script, orchestrating the entire
#          NVIDIA GPU configuration process for an LXC container.
# Content:
# *   Calls `parse_arguments` to retrieve the `CTID` from command-line input.
# *   Invokes `validate_inputs` to ensure all required arguments and environment variables are valid.
# *   Executes `check_container_exists` to confirm the target container is present on the host.
# *   Calls `configure_host_gpu_passthrough` to set up device mounts in the LXC configuration.
# *   Initiates `install_nvidia_software_in_container` to install NVIDIA drivers and CUDA within the container.
# *   Triggers `restart_container` to apply all configuration changes and activate the NVIDIA setup.
# *   Calls `exit_script 0` upon successful completion of all steps.
main() {
    parse_arguments "$@"
    validate_inputs
    check_container_exists
    configure_host_gpu_passthrough
    install_nvidia_software_in_container
    restart_container
    exit_script 0
}

# Call the main function
main "$@"
