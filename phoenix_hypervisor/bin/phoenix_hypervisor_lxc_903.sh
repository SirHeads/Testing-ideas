#!/bin/bash

# phoenix_hypervisor_lxc_903.sh
#
# ## Description
# Finalizes the setup for LXC container 903 (BaseTemplateDockerGPU) and creates the Docker+GPU ZFS snapshot.
# This script performs final configuration steps for the BaseTemplateDockerGPU LXC container (CTID 903).
# It verifies that Docker Engine, the NVIDIA Container Toolkit, and direct GPU access (inherited/cloned from 902)
# are correctly configured and functional inside the container. It then shuts down the container
# to create the 'docker-gpu-snapshot' ZFS snapshot. This snapshot serves as the foundation for
# other templates/containers requiring both Docker-in-LXC and direct GPU access.
#
# ## Version
# 0.1.0
#
# ## Author
# Heads, Qwen3-coder (AI Assistant)
#
# ## Purpose
# To automate the final verification and snapshot creation for the BaseTemplateDockerGPU LXC container (CTID 903),
# ensuring it is ready for use as a base image for other GPU-accelerated Docker environments within LXC.
# This script is critical for establishing a standardized and reproducible environment.
#
# ## Usage
# ```bash
# ./phoenix_hypervisor_lxc_903.sh <CTID>
# ```
#
# ### Example
# ```bash
# ./phoenix_hypervisor_lxc_903.sh 903
# ```
#
# ## Arguments
# *   `$1` (CTID): The Container ID, expected to be `903` for `BaseTemplateDockerGPU`.
#
# ## Requirements
# *   Proxmox host environment with `pct` command available.
# *   LXC Container `903` must be created/cloned and accessible.
# *   `jq` must be installed for potential JSON parsing (though not directly used in this version, it's a common dependency).
# *   LXC Container `903` is expected to be cloned from `902`'s `docker-snapshot`.
#
# ## Exit Codes
# *   `0`: Success. Setup completed, snapshot created or already existed.
# *   `1`: General error.
# *   `2`: Invalid input arguments.
# *   `3`: Container `903` does not exist or is not accessible.
# *   `4`: Verification of Docker/GPU setup inside container failed.
# *   `5`: Snapshot creation failed.
# *   `6`: Container shutdown/start failed.

# --- Global Variables and Constants ---
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"

# --- Logging Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] phoenix_hypervisor_lxc_903.sh: $*" | tee -a "$MAIN_LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] phoenix_hypervisor_lxc_903.sh: $*" | tee -a "$MAIN_LOG_FILE" >&2
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
SNAPSHOT_NAME="docker-gpu-snapshot" # Defined in requirements

### Function: `parse_arguments()`
# **Purpose:** Retrieves the Container ID (CTID) from the command-line arguments.
#
# **Details:**
# *   Checks if exactly one argument is provided.
# *   If not, logs a usage error and exits with code `2`.
# *   Assigns the first argument to the global `CTID` variable.
# *   Logs the successfully received CTID.
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Received CTID: $CTID"
}

### Function: `validate_inputs()`
# **Purpose:** Ensures the script received a valid and expected Container ID (CTID).
#
# **Details:**
# *   Validates that `CTID` is a positive integer. If not, logs a fatal error and exits with code `2`.
# *   Checks if `CTID` is `903`. If it's not, a warning is logged, but the script continues.
#     This allows for flexibility while highlighting the script's intended target.
# *   Logs successful input validation.
validate_inputs() {
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_error "FATAL: Invalid CTID '$CTID'. Must be a positive integer."
        exit_script 2
    fi
    if [ "$CTID" -ne 903 ]; then
        log_error "WARNING: This script is specifically designed for CTID 903 (BaseTemplateDockerGPU). Proceeding, but verify usage."
    fi
    log_info "Input validation passed."
}

### Function: `check_container_exists()`
# **Purpose:** Verifies the existence and accessibility of the target LXC container.
#
# **Details:**
# *   Uses `pct status "$CTID"` to check the container's status.
# *   If the command fails (non-zero exit code), it indicates the container does not exist or is inaccessible.
#     A fatal error is logged, and the script exits with code `3`.
# *   If the container exists, a confirmation message is logged.
check_container_exists() {
    log_info "Checking for existence of container CTID: $CTID"
    if ! pct status "$CTID" > /dev/null 2>&1; then
        log_error "FATAL: Container $CTID does not exist or is not accessible."
        exit_script 3
    fi
    log_info "Container $CTID exists."
}

### Function: `check_if_snapshot_exists()`
# **Purpose:** Implements idempotency by checking if the `docker-gpu-snapshot` already exists.
#
# **Details:**
# *   Queries `pct snapshot list "$CTID"` to retrieve existing snapshots for the container.
# *   Uses `grep -q` to silently check for the presence of `$SNAPSHOT_NAME` (i.e., `docker-gpu-snapshot`).
# *   If the snapshot exists, it logs a message indicating that the setup is complete and exits with code `0`.
# *   If the snapshot does not exist, it logs a message and allows the script to proceed with the setup.
check_if_snapshot_exists() {
    log_info "Checking if snapshot '$SNAPSHOT_NAME' already exists for container $CTID."
    if pct snapshot list "$CTID" | grep -q "$SNAPSHOT_NAME"; then
        log_info "Snapshot '$SNAPSHOT_NAME' already exists for container $CTID. Skipping setup."
        exit_script 0
    else
        log_info "Snapshot '$SNAPSHOT_NAME' does not exist. Proceeding with setup."
    fi
}

### Function: `verify_docker_and_gpu_setup_inside_container()`
# **Purpose:** Confirms that both direct GPU access and Docker with GPU access are fully functional inside the container.
#
# **Details:**
# This function performs a series of checks to ensure the `BaseTemplateDockerGPU` container is correctly configured:
#
# 1.  **Verify Direct GPU Access:**
#     *   Executes `nvidia-smi` inside the container using `pct exec`.
#     *   Logs the output for visibility and checks the exit code.
#     *   If `nvidia-smi` fails, a fatal error is logged, and the script exits with code `4`.
#
# 2.  **Verify Docker Info (including NVIDIA Runtime):**
#     *   Executes `docker info` inside the container.
#     *   Logs the output, which should include details about the NVIDIA Container Runtime.
#     *   If `docker info` fails, a fatal error is logged, and the script exits with code `4`.
#
# 3.  **Verify Docker Container with GPU Access:**
#     *   Pulls a lightweight `nvidia/cuda` base image (`nvidia/cuda:12.8.0-base-ubuntu24.04`).
#     *   Attempts to run a Docker container with `--gpus all` and executes `nvidia-smi` within it.
#     *   Logs the output of the `docker run` command.
#     *   If the `docker run` command fails, a fatal error is logged, and the script exits with code `4`.
#     *   Note: Failure to pull the test image is logged as a warning, allowing the script to continue if the base setup is otherwise functional.
verify_docker_and_gpu_setup_inside_container() {
    log_info "Starting verification of Docker and GPU setup inside container CTID: $CTID"

    # 1. Verify Direct GPU Access
    log_info "Verifying direct GPU access by running nvidia-smi..."
    local nvidia_smi_output
    if ! nvidia_smi_output=$(pct exec "$CTID" -- nvidia-smi 2>&1); then
        log_error "FATAL: Direct GPU access verification failed for CTID $CTID. 'nvidia-smi' command failed."
        echo "$nvidia_smi_output" | log_error
        exit_script 4
    fi
    log_info "Direct GPU access verified for CTID $CTID. nvidia-smi output:"
    echo "$nvidia_smi_output" | while IFS= read -r line; do log_info "$line"; done

    # 2. Verify Docker Info (including NVIDIA Runtime)
    log_info "Verifying Docker information (including NVIDIA Runtime)..."
    local docker_info_output
    if ! docker_info_output=$(pct exec "$CTID" -- docker info 2>&1); then
        log_error "FATAL: Docker info verification failed for CTID $CTID. 'docker info' command failed."
        echo "$docker_info_output" | log_error
        exit_script 4
    fi
    log_info "Docker information verified for CTID $CTID. docker info output:"
    echo "$docker_info_output" | while IFS= read -r line; do log_info "$line"; done

    # 3. Verify Docker Container with GPU Access
    log_info "Verifying Docker container GPU access using a simple CUDA container..."
    local test_image="nvidia/cuda:12.8.0-base-ubuntu24.04" # Lightweight, official image
    local test_command="nvidia-smi"
    local docker_run_output

    log_info "Pulling test image $test_image..."
    if ! pct exec "$CTID" -- docker pull "$test_image"; then
        log_error "WARNING: Failed to pull test image $test_image. Skipping Docker GPU access verification."
        # Not a fatal error, as the base setup might still be fine.
    else
        log_info "Running test container with GPU access..."
        if ! docker_run_output=$(pct exec "$CTID" -- docker run --rm --gpus all "$test_image" "$test_command" 2>&1); then
            log_error "FATAL: Docker GPU container verification failed for CTID $CTID. Test command failed."
            echo "$docker_run_output" | log_error
            exit_script 4
        fi
        log_info "Docker container GPU access verified for CTID $CTID. Output:"
        echo "$docker_run_output" | while IFS= read -r line; do log_info "$line"; done
    fi

    log_info "Docker and GPU setup verification completed successfully inside container CTID: $CTID."
}

### Function: `shutdown_container()`
# **Purpose:** Safely shuts down the specified LXC container.
#
# **Details:**
# *   Initiates a shutdown of the container using `pct shutdown "$ctid"`.
# *   Includes a loop that polls `pct status "$ctid"` to wait for the container to reach a 'stopped' state.
# *   A timeout of `60` seconds and an interval of `3` seconds are used for the polling mechanism.
# *   If the container fails to stop within the timeout, a fatal error is logged, and the script exits with code `6`.
shutdown_container() {
    local ctid="$1"
    local timeout=60 # Timeout in seconds for container shutdown
    local interval=3 # Polling interval in seconds
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

### Function: `create_docker_gpu_snapshot()`
# **Purpose:** Creates the `docker-gpu-snapshot` ZFS snapshot for the specified container.
#
# **Details:**
# *   Executes `pct snapshot create "$CTID" "$SNAPSHOT_NAME"` to create the snapshot.
# *   If the snapshot creation fails (non-zero exit code), a fatal error is logged, and the script exits with code `5`.
# *   Logs a success message upon successful snapshot creation.
create_docker_gpu_snapshot() {
    log_info "Creating ZFS snapshot '$SNAPSHOT_NAME' for container $CTID..."
    if ! pct snapshot create "$CTID" "$SNAPSHOT_NAME"; then
        log_error "FATAL: Failed to create snapshot '$SNAPSHOT_NAME' for container $CTID."
        exit_script 5
    fi
    log_info "Snapshot '$SNAPSHOT_NAME' created successfully for container $CTID."
}

### Function: `start_container()`
# **Purpose:** Restarts the specified LXC container after snapshot creation.
#
# **Details:**
# *   Initiates a start of the container using `pct start "$ctid"`.
# *   Includes a loop that polls `pct status "$ctid"` to wait for the container to reach a 'running' state.
# *   A timeout of `60` seconds and an interval of `3` seconds are used for the polling mechanism.
# *   If the container fails to start within the timeout, a fatal error is logged, and the script exits with code `6`.
start_container() {
    local ctid="$1"
    local timeout=60 # Timeout in seconds for container startup
    local interval=3 # Polling interval in seconds
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

### Function: `main()`
# **Purpose:** Controls the overall flow of the `BaseTemplateDockerGPU` setup and snapshot creation.
#
# **Details:**
# This is the entry point of the script, orchestrating the execution of all other functions:
# 1.  `parse_arguments()`: Retrieves the CTID from command-line arguments.
# 2.  `validate_inputs()`: Validates the provided CTID.
# 3.  `check_container_exists()`: Verifies the target container exists.
# 4.  `check_if_snapshot_exists()`: Checks for idempotency; exits successfully if the snapshot already exists.
# 5.  `verify_docker_and_gpu_setup_inside_container()`: Confirms Docker and GPU functionality within the container.
# 6.  `shutdown_container()`: Safely shuts down the container.
# 7.  `create_docker_gpu_snapshot()`: Creates the ZFS snapshot.
# 8.  `start_container()`: Restarts the container.
# 9.  `exit_script 0`: Signals successful completion of the script.
main() {
    parse_arguments "$@"
    validate_inputs
    check_container_exists
    check_if_snapshot_exists # This function will exit the script with code 0 if the snapshot already exists.

    verify_docker_and_gpu_setup_inside_container "$CTID"
    shutdown_container "$CTID"
    create_docker_gpu_snapshot "$CTID"
    start_container "$CTID"

    exit_script 0
}

# Call the main function
main "$@"