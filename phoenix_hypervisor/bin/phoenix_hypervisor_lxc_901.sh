#!/bin/bash
#
# File: phoenix_hypervisor_lxc_901.sh
# Description: Finalizes the setup for LXC container 901 (BaseTemplateGPU) and creates
#              the 'gpu-snapshot' ZFS snapshot. This script integrates NVIDIA drivers
#              and CUDA toolkit, verifies GPU access, and prepares the container
#              as a template for GPU-accelerated workloads. Comments are optimized
#              for Retrieval Augmented Generation (RAG), facilitating effective
#              chunking and vector database indexing.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script is a crucial step in building the Phoenix Hypervisor's template hierarchy,
# specifically for environments requiring NVIDIA GPU capabilities. The 'gpu-snapshot'
# ensures a consistent and pre-configured base for all subsequent GPU-dependent LXC containers.
#
# Usage:
#   ./phoenix_hypervisor_lxc_901.sh <CTID>
#
# Arguments:
#   - CTID (integer): The Container ID, which must be `901` for the BaseTemplateGPU.
#
# Requirements:
#   - Proxmox VE host environment with `pct` command available.
#   - LXC container `901` must be pre-created/cloned from BaseTemplate (CTID 900) and running.
#   - `jq` for JSON parsing (used to retrieve global NVIDIA settings).
#   - `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_common_nvidia.sh` must be present and executable.
#   - Global NVIDIA settings (driver version, repository URL, runfile URL) must be defined
#     in `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`.
#   - Appropriate permissions to manage LXC containers and ZFS snapshots.
#
# Exit Codes:
#   0: Success (Setup completed, snapshot created or already existed).
#   1: General error.
#   2: Invalid input arguments.
#   3: Container 901 does not exist or is not accessible.
#   4: NVIDIA driver/CUDA installation/configuration failed.
#   5: Snapshot creation failed.
#   6: Container shutdown/start failed.

# --- Global Variables and Constants ---
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"
LXC_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json" # Needed for global NVIDIA settings
HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json" # Needed for global NVIDIA settings

# --- Logging Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] phoenix_hypervisor_lxc_901.sh: $*" | tee -a "$MAIN_LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] phoenix_hypervisor_lxc_901.sh: $*" | tee -a "$MAIN_LOG_FILE" >&2
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
SNAPSHOT_NAME="gpu-snapshot" # Defined in requirements

# =====================================================================================
# Function: parse_arguments
# Description: Parses and validates the command-line arguments, expecting a single
#              argument representing the Container ID (CTID).
#
# Parameters:
#   - $@: All command-line arguments.
#
# Global Variables Modified:
#   - `CTID`: Stores the Container ID extracted from the arguments.
#
# Exit Conditions:
#   - Exits with code 2 if an incorrect number of arguments is provided.
#
# RAG Keywords: argument parsing, command-line interface, script input, CTID.
# =====================================================================================
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Received CTID: $CTID"
}

# =====================================================================================
# Function: validate_inputs
# Description: Validates the provided Container ID (CTID) to ensure it is a positive
#              integer and, specifically, that it matches `901` as this script is
#              tailored for the BaseTemplateGPU. A warning is logged if the CTID is not 901.
#
# Parameters: None (operates on global script variable `CTID`)
#
# Exit Conditions:
#   - Exits with code 2 if `CTID` is not a valid positive integer.
#
# RAG Keywords: input validation, CTID validation, BaseTemplateGPU, script specificity.
# =====================================================================================
# =====================================================================================
validate_inputs() {
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_error "FATAL: Invalid CTID '$CTID'. Must be a positive integer."
        exit_script 2
    fi
    if [ "$CTID" -ne 901 ]; then
        log_error "WARNING: This script is specifically designed for CTID 901 (BaseTemplateGPU). Proceeding, but verify usage."
    fi
    log_info "Input validation passed."
}

# =====================================================================================
# Function: check_container_exists
# Description: Verifies the existence and manageability of the target LXC container
#              (CTID 901). This is a crucial sanity check before proceeding with
#              any GPU-specific configuration or snapshot operations.
#
# Parameters: None (operates on global script variable `CTID`)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct status`).
#
# Exit Conditions:
#   - Exits with code 3 if the container does not exist or is not accessible.
#
# RAG Keywords: container existence, LXC status, BaseTemplateGPU, Proxmox `pct`, error handling.
# =====================================================================================
# =====================================================================================
check_container_exists() {
    log_info "Checking for existence of container CTID: $CTID"
    if ! pct status "$CTID" > /dev/null 2>&1; then
        log_error "FATAL: Container $CTID does not exist or is not accessible."
        exit_script 3
    fi
    log_info "Container $CTID exists."
}

# =====================================================================================
# Function: check_if_snapshot_exists
# Description: Checks if the 'gpu-snapshot' ZFS snapshot already exists for the
#              target container (CTID 901). This function ensures idempotency,
#              preventing redundant snapshot creation if the setup was previously completed.
#
# Parameters: None (operates on global script variables `CTID` and `SNAPSHOT_NAME`)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct snapshot list`).
#   - `grep`: Used for parsing snapshot list output.
#
# Exit Conditions:
#   - Exits with code 0 if the 'gpu-snapshot' already exists.
#   - Continues execution if the snapshot does not exist.
#
# RAG Keywords: ZFS snapshot, idempotency, GPU template, container state, Proxmox `pct`.
# =====================================================================================
# =====================================================================================
check_if_snapshot_exists() {
    log_info "Checking if snapshot '$SNAPSHOT_NAME' already exists for container $CTID."
    if pct snapshot list "$CTID" | grep -q "$SNAPSHOT_NAME"; then
        log_info "Snapshot '$SNAPSHOT_NAME' already exists for container $CTID. Skipping setup."
        exit_script 0
    else
        log_info "Snapshot '$SNAPSHOT_NAME' does not exist. Proceeding with setup."
    fi
}

# =====================================================================================
# Function: install_and_configure_nvidia_in_container
# Description: Orchestrates the installation and configuration of NVIDIA drivers and
#              CUDA toolkit within the BaseTemplateGPU container (CTID 901). It
#              delegates the core installation logic to a common NVIDIA script,
#              passing necessary global NVIDIA settings and a predefined GPU assignment.
#
# Parameters: None (operates on global script variable `CTID`)
#
# Dependencies:
#   - `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_common_nvidia.sh`: The common script for NVIDIA setup.
#   - `jq`: Used to extract global NVIDIA settings from `LXC_CONFIG_FILE`.
#
# Global Variables Accessed:
#   - `LXC_CONFIG_FILE`: To retrieve global NVIDIA configuration.
#
# Exit Conditions:
#   - Exits with code 4 if the common NVIDIA script is missing/not executable,
#     global NVIDIA settings are incomplete, or the NVIDIA setup fails.
#
# RAG Keywords: NVIDIA driver installation, CUDA toolkit, GPU configuration,
#               LXC container, BaseTemplateGPU, common script, error handling.
# =====================================================================================
# =====================================================================================
install_and_configure_nvidia_in_container() {
    log_info "Starting NVIDIA driver/CUDA setup inside container CTID: $CTID"
    local nvidia_script="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_common_nvidia.sh"

    if [ ! -f "$nvidia_script" ] || [ ! -x "$nvidia_script" ]; then
        log_error "FATAL: Common NVIDIA script not found or not executable: $nvidia_script"
        exit_script 4
    fi

    # Extract global NVIDIA settings from LXC_CONFIG_FILE
    local nvidia_driver_version=$(jq -r '.nvidia_driver_version' "$LXC_CONFIG_FILE")
    local nvidia_repo_url=$(jq -r '.nvidia_repo_url' "$LXC_CONFIG_FILE")
    local nvidia_runfile_url=$(jq -r '.nvidia_runfile_url' "$LXC_CONFIG_FILE")

    if [ -z "$nvidia_driver_version" ] || [ -z "$nvidia_repo_url" ] || [ -z "$nvidia_runfile_url" ]; then
        log_error "FATAL: Global NVIDIA settings (driver version, repo URL, runfile URL) are incomplete in $LXC_CONFIG_FILE."
        exit_script 4
    fi

    # For CTID 901, we assign GPUs "0,1" as per the project summary for BaseTemplateGPU
    local gpu_assignment="0,1" 

    log_info "Executing common NVIDIA setup script for CTID $CTID with GPU_ASSIGNMENT=$gpu_assignment..."
    GPU_ASSIGNMENT="$gpu_assignment" \
    NVIDIA_DRIVER_VERSION="$nvidia_driver_version" \
    NVIDIA_REPO_URL="$nvidia_repo_url" \
    NVIDIA_RUNFILE_URL="$nvidia_runfile_url" \
    "$nvidia_script" "$CTID"
    local exit_status=$?

    if [ "$exit_status" -ne 0 ]; then
        log_error "FATAL: Common NVIDIA setup script failed for CTID $CTID with exit code $exit_status."
        exit_script 4
    fi
    log_info "NVIDIA driver/CUDA setup completed successfully inside container $CTID."
}

# =====================================================================================
# Function: verify_nvidia_setup_inside_container
# Description: Verifies the successful installation and configuration of NVIDIA drivers
#              and CUDA toolkit within the specified LXC container (CTID) by executing
#              the `nvidia-smi` command. The output is logged for diagnostic purposes.
#
# Parameters:
#   - $1 (CTID): The Container ID where NVIDIA setup needs verification.
#
# Dependencies:
#   - `pct exec`: For executing commands inside the LXC container.
#   - `nvidia-smi`: NVIDIA System Management Interface tool, expected to be available in the container.
#
# Exit Conditions:
#   - Exits with code 4 if the `nvidia-smi` command fails, indicating a problem with the NVIDIA setup.
#
# RAG Keywords: NVIDIA verification, GPU driver check, CUDA setup, `nvidia-smi`,
#               LXC container, error handling, diagnostic.
# =====================================================================================
# =====================================================================================
verify_nvidia_setup_inside_container() {
    log_info "Verifying NVIDIA setup inside container CTID: $CTID by running nvidia-smi."
    local nvidia_smi_output
    if ! nvidia_smi_output=$(pct exec "$CTID" -- nvidia-smi 2>&1); then
        log_error "FATAL: NVIDIA setup verification failed for CTID $CTID. 'nvidia-smi' command failed."
        echo "$nvidia_smi_output" | log_error # Log the output of nvidia-smi for debugging
        exit_script 4
    fi
    log_info "NVIDIA setup verification successful for CTID $CTID. nvidia-smi output:"
    echo "$nvidia_smi_output" | while IFS= read -r line; do log_info "$line"; done
}

# =====================================================================================
# Function: shutdown_container
# Description: Safely shuts down the specified LXC container (CTID). It initiates
#              the shutdown process using `pct shutdown` and then polls the container's
#              status until it reaches a 'stopped' state or a timeout occurs.
#
# Parameters:
#   - $1 (CTID): The Container ID of the LXC container to shut down.
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct shutdown`, `pct status`).
#
# Exit Conditions:
#   - Exits with code 6 if the shutdown initiation fails or if the container
#     does not stop within the defined timeout.
#
# RAG Keywords: container shutdown, LXC management, Proxmox `pct`, graceful shutdown,
#               timeout, error handling.
# =====================================================================================
# =====================================================================================
shutdown_container() {
    local ctid="$1"
    local timeout=60 # seconds
    local interval=3 # seconds
    local elapsed_time=0

    log_info "Initiating shutdown of container $ctid..."
    if ! pct shutdown "$ctid"; then
        log_error "FATAL: Failed to initiate shutdown for container $ctid."
        exit_script 6
    fi

    log_info "Waiting for container $ctid to stop..."
    while [ "$elapsed_time" -lt "$timeout" ]; do
        if pct status "$ctid" | grep -q "status: stopped"; then
            log_info "Container $ctid is stopped."
            return 0
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    log_error "FATAL: Container $ctid did not stop within ${timeout} seconds."
    exit_script 6
}

# =====================================================================================
# Function: create_gpu_snapshot
# Description: Creates the 'gpu-snapshot' ZFS snapshot for the specified LXC container
#              (CTID 901). This snapshot captures the state of the BaseTemplateGPU
#              after NVIDIA drivers and CUDA have been successfully integrated,
#              making it ready for cloning into GPU-accelerated LXC containers.
#
# Parameters: None (operates on global script variables `CTID` and `SNAPSHOT_NAME`)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct snapshot create`).
#
# Exit Conditions:
#   - Exits with code 5 if the snapshot creation fails.
#
# RAG Keywords: ZFS snapshot, GPU template, container imaging, NVIDIA integration,
#               Proxmox `pct`, error handling.
# =====================================================================================
# =====================================================================================
create_gpu_snapshot() {
    log_info "Creating ZFS snapshot '$SNAPSHOT_NAME' for container $CTID..."
    if ! pct snapshot create "$CTID" "$SNAPSHOT_NAME"; then
        log_error "FATAL: Failed to create snapshot '$SNAPSHOT_NAME' for container $CTID."
        exit_script 5
    fi
    log_info "Snapshot '$SNAPSHOT_NAME' created successfully for container $CTID."
}

# =====================================================================================
# Function: start_container
# Description: Restarts the specified LXC container (CTID) after the ZFS snapshot
#              has been successfully created. It initiates the startup using `pct start`
#              and then polls the container's status until it reaches a 'running' state
#              or a timeout occurs.
#
# Parameters:
#   - $1 (CTID): The Container ID of the LXC container to start.
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct start`, `pct status`).
#
# Exit Conditions:
#   - Exits with code 6 if the startup initiation fails or if the container
#     does not start within the defined timeout.
#
# RAG Keywords: container startup, LXC management, Proxmox `pct`, container restart,
#               timeout, error handling.
# =====================================================================================
# =====================================================================================
start_container() {
    local ctid="$1"
    local timeout=60 # seconds
    local interval=3 # seconds
    local elapsed_time=0

    log_info "Starting container $ctid after snapshot creation..."
    if ! pct start "$ctid"; then
        log_error "FATAL: Failed to start container $ctid."
        exit_script 6
    fi

    log_info "Waiting for container $ctid to start..."
    while [ "$elapsed_time" -lt "$timeout" ]; do
        if pct status "$ctid" | grep -q "status: running"; then
            log_info "Container $ctid is running."
            return 0
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    log_error "FATAL: Container $ctid did not start within ${timeout} seconds."
    exit_script 6
}

# =====================================================================================
# Function: main
# Description: The main entry point for the BaseTemplateGPU (CTID 901) setup script.
#              It orchestrates the entire process of preparing the GPU-enabled template,
#              including argument parsing, input validation, checking for existing
#              snapshots, installing and verifying NVIDIA components, shutting down,
#              creating the 'gpu-snapshot', and restarting the container.
#
# Parameters:
#   - $@: All command-line arguments passed to the script.
#
# Dependencies:
#   - `parse_arguments()`
#   - `validate_inputs()`
#   - `check_container_exists()`
#   - `check_if_snapshot_exists()`
#   - `install_and_configure_nvidia_in_container()`
#   - `verify_nvidia_setup_inside_container()`
#   - `shutdown_container()`
#   - `create_gpu_snapshot()`
#   - `start_container()`
#   - `exit_script()`
#
# RAG Keywords: main function, script entry point, BaseTemplateGPU setup, ZFS snapshot,
#               NVIDIA configuration, LXC management.
# =====================================================================================
# =====================================================================================
main() {
    parse_arguments "$@"
    validate_inputs
    check_container_exists
    check_if_snapshot_exists # Exits 0 if snapshot already exists

    install_and_configure_nvidia_in_container
    verify_nvidia_setup_inside_container "$CTID"
    shutdown_container "$CTID"
    create_gpu_snapshot "$CTID"
    start_container "$CTID"

    exit_script 0
}

# Call the main function
main "$@"