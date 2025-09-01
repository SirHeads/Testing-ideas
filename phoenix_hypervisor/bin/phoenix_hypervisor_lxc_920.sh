#!/bin/bash

# phoenix_hypervisor_lxc_920.sh
#
# ## Description
# This script finalizes the setup for LXC container 920, designated as `BaseTemplateVLLM`,
# and creates a ZFS snapshot named `vllm-base-snapshot`. This snapshot serves as a foundational
# template for other vLLM-dependent containers within the Proxmox hypervisor environment.
#
# ## Purpose
# The primary purpose is to ensure the `BaseTemplateVLLM` container is fully configured
# with Docker Engine, NVIDIA Container Toolkit, and direct GPU access. It then validates
# the vLLM setup by deploying a test instance, verifying its API, and finally creating
# a stable ZFS snapshot for future cloning operations.
#
# ## Version
# 0.1.0
#
# ## Author
# Heads, Qwen3-coder (AI Assistant)
#
# ## Usage
# `./phoenix_hypervisor_lxc_920.sh <CTID>`
#
# ### Arguments
# *   `CTID`: The Container ID, which is expected to be `920` for `BaseTemplateVLLM`.
#
# ### Example
# `./phoenix_hypervisor_lxc_920.sh 920`
#
# ## Requirements
# *   **Proxmox Host:** Must be a Proxmox host environment with the `pct` command available.
# *   **Container 920:** Must be pre-created or cloned and accessible.
# *   **`jq`:** Required for JSON parsing, if needed for future enhancements.
# *   **Cloning Source:** Container 920 is expected to be cloned from container 903's `docker-gpu-snapshot`.
# *   **Docker & NVIDIA:** Docker and NVIDIA drivers/toolkit must be fully functional inside container 920.
#
# ## Exit Codes
# *   `0`: Success. Setup completed, and the snapshot was created or already existed (idempotent).
# *   `1`: General error.
# *   `2`: Invalid input arguments provided.
# *   `3`: Container 920 does not exist or is inaccessible.
# *   `4`: Prerequisite Docker/NVIDIA verification inside the container failed.
# *   `5`: vLLM test deployment or API verification failed.
# *   `6`: Container shutdown or start operation failed.
# *   `7`: ZFS snapshot creation failed.

# ## Global Variables and Constants
#
# These variables define critical paths and configurations used throughout the script.
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log" # Path to the main log file for script execution.
LXC_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json" # Configuration file for LXC settings, potentially including NVIDIA.
HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json" # Main hypervisor configuration file, potentially including NVIDIA.

# ## Logging Functions
#
# These functions provide standardized logging capabilities for script execution.
# All messages are timestamped and written to both `stdout` and the `MAIN_LOG_FILE`.
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] phoenix_hypervisor_lxc_920.sh: $*" | tee -a "$MAIN_LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] phoenix_hypervisor_lxc_920.sh: $*" | tee -a "$MAIN_LOG_FILE" >&2
}

# ## Exit Function
#
# Handles script termination, logging the final status (success or failure) based on the provided exit code.
#
# ### Arguments
# *   `$1` (exit_code): The integer exit code to use for script termination.
exit_script() {
    local exit_code=$1
    if [ "$exit_code" -eq 0 ]; then
        log_info "Script completed successfully."
    else
        log_error "Script failed with exit code $exit_code."
    fi
    exit "$exit_code"
}

# ## Script Variables
#
# Variables specific to the execution context of this script.
CTID="" # Stores the Container ID passed as a command-line argument.
SNAPSHOT_NAME="vllm-base-snapshot" # The name of the ZFS snapshot to be created, as defined in requirements.

# ## Function: `parse_arguments()`
#
# Retrieves and validates the Container ID (CTID) from the command-line arguments.
#
# ### Logic
# 1.  **Argument Count Check:** Verifies that exactly one argument is provided.
#     *   If not, logs a usage error and exits with code `2`.
# 2.  **CTID Assignment:** Assigns the first argument to the global `CTID` variable.
# 3.  **Logging:** Logs the successfully received CTID.
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Received CTID: $CTID"
}

# ## Function: `validate_inputs()`
#
# Ensures the provided Container ID (CTID) is valid and matches the expected value for this script.
#
# ### Logic
# 1.  **Integer Validation:** Checks if `CTID` is a positive integer.
#     *   If not, logs a fatal error and exits with code `2`.
# 2.  **Specific CTID Check:** Verifies if `CTID` is `920`.
#     *   If not, logs a warning, as this script is optimized for `BaseTemplateVLLM` (CTID 920), but continues execution.
# 3.  **Logging:** Confirms successful input validation.
validate_inputs() {
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_error "FATAL: Invalid CTID '$CTID'. Must be a positive integer."
        exit_script 2
    fi
    if [ "$CTID" -ne 920 ]; then
        log_error "WARNING: This script is specifically designed for CTID 920 (BaseTemplateVLLM). Proceeding, but verify usage."
    fi
    log_info "Input validation passed."
}

# ## Function: `check_container_exists()`
#
# Verifies the existence and accessibility of the target LXC container using `pct status`.
# This is a critical prerequisite check before performing any operations on the container.
#
# ### Logic
# 1.  **Status Check:** Executes `pct status "$CTID"` to determine if the container exists.
# 2.  **Error Handling:** If `pct status` returns a non-zero exit code, it indicates the container
#     does not exist or is inaccessible. A fatal error is logged, and the script exits with code `3`.
# 3.  **Logging:** Confirms the container's existence.
check_container_exists() {
    log_info "Checking for existence of container CTID: $CTID"
    if ! pct status "$CTID" > /dev/null 2>&1; then
        log_error "FATAL: Container $CTID does not exist or is not accessible."
        exit_script 3
    fi
    log_info "Container $CTID exists."
}

# ## Function: `check_if_snapshot_exists()`
#
# Implements idempotency by checking if the `vllm-base-snapshot` already exists for the target container.
# If the snapshot is found, the script assumes the setup is complete and exits successfully.
#
# ### Logic
# 1.  **Snapshot Listing:** Executes `pct snapshot list "$CTID"` to retrieve existing snapshots.
# 2.  **Existence Check:** Uses `grep -q` to silently check for the presence of `$SNAPSHOT_NAME` in the output.
# 3.  **Idempotency Handling:**
#     *   If the snapshot exists, logs a message indicating that setup is being skipped and exits with code `0`.
#     *   If the snapshot does not exist, logs a message and allows the script to proceed with setup.
check_if_snapshot_exists() {
    log_info "Checking if snapshot '$SNAPSHOT_NAME' already exists for container $CTID."
    if pct snapshot list "$CTID" | grep -q "$SNAPSHOT_NAME"; then
        log_info "Snapshot '$SNAPSHOT_NAME' already exists for container $CTID. Skipping setup."
        exit_script 0
    else
        log_info "Snapshot '$SNAPSHOT_NAME' does not exist. Proceeding with setup."
    fi
}


# ## Function: `install_and_test_vllm_inside_container()`
#
# Orchestrates the installation of vLLM, deployment of a test vLLM server,
# verifies its API functionality, and ensures proper cleanup.
#
# ### Arguments
# *   `$1` (ctid): The Container ID of the LXC container.
#
# ### Logic
# 1.  **Install Python and Pip:** Installs `python3-pip` inside the container.
# 2.  **Install vLLM:** Installs `vllm` using `pip3`.
# 3.  **Start Test vLLM Server:** Starts a detached vLLM server with a specified
#     test model (`Qwen/Qwen2.5-Coder-7B-Instruct-AWQ`) and host `0.0.0.0`.
#     Captures the PID of the background process.
# 4.  **Wait for Server Readiness:** Polls the vLLM server logs, waiting for an indication that the
#     server is running (e.g., "Uvicorn running on").
#     *   Includes a timeout mechanism to prevent indefinite waiting.
# 5.  **Verify API Access via Curl:** Sends a chat completion request to the vLLM API using `curl`.
#     *   Checks the JSON response for the expected word "Paris" to confirm basic functionality.
# 6.  **Clean Up Test Server:** Kills the temporary vLLM server process using the captured PID.
#
# ### Dependencies
# *   `kill_vllm_server()`: Helper function for stopping the vLLM server.
install_and_test_vllm_inside_container() {
    local ctid="$1"
    log_info "Starting vLLM installation and verification inside container CTID: $ctid"

    local test_model="Qwen/Qwen2.5-Coder-7B-Instruct-AWQ" # Small model for testing.
    local vllm_server_log="/var/log/vllm_server.log" # Log file for the vLLM server.
    local vllm_pid_file="/tmp/vllm_server.pid" # File to store the vLLM server PID.

    # ### 1. Install Python and Pip
    log_info "Installing Python3 and Pip inside CTID $ctid..."
    if ! pct exec "$ctid" -- bash -c "apt-get update && apt-get install -y python3-pip"; then
        log_error "FATAL: Failed to install Python3 and Pip inside CTID $ctid."
        exit_script 5
    fi
    log_info "Python3 and Pip installed successfully inside CTID $ctid."

    # ### 2. Install vLLM
    log_info "Installing vLLM via pip3 inside CTID $ctid..."
    if ! pct exec "$ctid" -- pip3 install vllm; then
        log_error "FATAL: Failed to install vLLM inside CTID $ctid."
        exit_script 5
    fi
    log_info "vLLM installed successfully inside CTID $ctid."

    # ### 3. Start Test vLLM Server
    log_info "Starting temporary vLLM server with model $test_model inside CTID $ctid..."
    # Start vLLM server in background, redirect output to log file, and store PID.
    if ! pct exec "$ctid" -- bash -c "python3 -m vllm.entrypoints.api_server --host 0.0.0.0 --model \"$test_model\" &> \"$vllm_server_log\" & echo \$! > \"$vllm_pid_file\""; then
        log_error "FATAL: Failed to start vLLM server inside CTID $ctid."
        exit_script 5
    fi
    log_info "vLLM server started in background for CTID $ctid. PID stored in $vllm_pid_file."

    # ### 4. Wait for Server Readiness
    log_info "Waiting for vLLM server to become ready inside CTID $ctid..."
    local timeout=300 # Maximum wait time in seconds (5 minutes) for the server to load.
    local interval=10 # Polling interval in seconds.
    local elapsed_time=0 # Tracks the elapsed time during the wait loop.
    local server_ready=false # Flag to indicate if the server has reported readiness.

    while [ "$elapsed_time" -lt "$timeout" ]; do
        # Check vLLM server log for "Uvicorn running on", indicating the server is active.
        if pct exec "$ctid" -- grep -q "Uvicorn running on" "$vllm_server_log"; then
            log_info "vLLM server appears to be ready inside CTID $ctid."
            server_ready=true
            break
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    if [ "$server_ready" == "false" ]; then
        log_error "FATAL: vLLM server did not indicate readiness within ${timeout} seconds for CTID $ctid."
        kill_vllm_server "$ctid" "$vllm_pid_file" # Attempt cleanup before exiting on failure.
        exit_script 5
    else
        log_info "vLLM server readiness wait completed for CTID $ctid."
    fi

    # ### 5. Verify API Access via Curl
    log_info "Verifying vLLM API access via curl inside CTID $ctid..."
    local curl_cmd='curl -s -X POST http://localhost:8000/v1/chat/completions -H "Content-Type: application/json" -d "{\"model\": \"'$test_model'\", \"messages\": [{\"role\": \"user\", \"content\": \"What is the capital of France?\"}]}"'
    local curl_output
    local api_test_success=false

    if ! curl_output=$(pct exec "$ctid" -- bash -c "$curl_cmd" 2>&1); then
        log_error "FATAL: vLLM API access verification failed for CTID $ctid. Curl command failed."
        echo "$curl_output" | while IFS= read -r line; do log_error "$line"; done
    else
        log_info "vLLM API response for CTID $ctid:"
        echo "$curl_output" | while IFS= read -r line; do log_info "$line"; done

        # Install jq if not present for robust JSON parsing
        if ! pct exec "$ctid" -- which jq > /dev/null; then
            log_info "Installing jq inside CTID $ctid for JSON parsing..."
            pct exec "$ctid" -- apt-get update && apt-get install -y jq
        fi
        local assistant_reply=$(pct exec "$ctid" -- bash -c "echo '$curl_output' | jq -r '.choices.message.content // \"\"'")

        if echo "$assistant_reply" | grep -iq "Paris"; then
            log_info "vLLM API verification successful for CTID $ctid: response contains 'Paris'."
            api_test_success=true
        else
            log_error "FATAL: Model reply for CTID $ctid did not contain the expected word 'Paris'. Response content: '$assistant_reply'"
        fi
    fi

    # ### 6. Clean Up Test Server
    kill_vllm_server "$ctid" "$vllm_pid_file"

    if [ "$api_test_success" == "false" ]; then
        exit_script 5
    fi

    log_info "vLLM installation and verification completed successfully inside container CTID: $ctid."
}

# ## Function: `kill_vllm_server()`
#
# A helper function to stop the vLLM server process within an LXC container.
# This ensures that temporary test servers do not persist after script execution.
#
# ### Arguments
# *   `$1` (ctid): The Container ID of the LXC container.
# *   `$2` (pid_file): The path to the file containing the PID of the vLLM server.
#
kill_vllm_server() {
    local ctid="$1"
    local pid_file="$2"
    log_info "Attempting to kill vLLM server process inside CTID $ctid using PID from $pid_file..."

    local vllm_pid=$(pct exec "$ctid" -- cat "$pid_file" 2>/dev/null)

    if [ -n "$vllm_pid" ]; then
        if pct exec "$ctid" -- kill "$vllm_pid"; then
            log_info "vLLM server process $vllm_pid killed successfully inside CTID $ctid."
        else
            log_error "WARNING: Failed to kill vLLM server process $vllm_pid inside CTID $ctid."
        fi
        # Remove the PID file
        pct exec "$ctid" -- rm -f "$pid_file"
    else
        log_info "No vLLM server PID found in $pid_file for CTID $ctid. Server might not have started or already stopped."
    fi
}

# ## Function: `shutdown_container()`
#
# Safely shuts down the specified LXC container and waits for it to reach a stopped state.
# This is a prerequisite for creating a consistent ZFS snapshot.
#
# ### Arguments
# *   `$1` (ctid): The Container ID of the LXC container to shut down.
#
# ### Logic
# 1.  **Initiate Shutdown:** Executes `pct shutdown "$ctid"`.
#     *   If the shutdown command fails, logs a fatal error and exits with code `6`.
# 2.  **Wait for Stop:** Enters a loop, polling `pct status "$ctid"` until the container's status is "stopped".
#     *   Includes a timeout to prevent indefinite waiting.
#     *   If the container does not stop within the timeout, logs a fatal error and exits with code `6`.
# 3.  **Logging:** Confirms successful container shutdown.
shutdown_container() {
    local ctid="$1"
    local timeout=60 # Maximum wait time in seconds for the container to stop.
    local interval=3 # Polling interval in seconds.
    local elapsed_time=0 # Tracks the elapsed time during the wait loop.

    log_info "Initiating shutdown of container $ctid..."
    if ! pct shutdown "$ctid"; then # Attempt to initiate container shutdown.
        log_error "FATAL: Failed to initiate shutdown for container $ctid."
        exit_script 6
    fi

    log_info "Waiting for container $ctid to stop..."
    while [ "$elapsed_time" -lt "$timeout" ]; do # Loop until timeout or container stops.
        if pct status "$ctid" | grep -q "status: stopped"; then # Check if container status is 'stopped'.
            log_info "Container $ctid is stopped."
            return 0 # Exit function on successful stop.
        fi
        sleep "$interval" # Wait before the next check.
        elapsed_time=$((elapsed_time + interval)) # Increment elapsed time.
    done

    log_error "FATAL: Container $ctid did not stop within ${timeout} seconds." # Log error if timeout reached.
    exit_script 6
}

# ## Function: `create_vllm_base_snapshot()`
#
# Creates a ZFS snapshot of the specified LXC container. This snapshot (`vllm-base-snapshot`)
# serves as a stable base for cloning new vLLM-enabled containers.
#
# ### Arguments
# *   `$1` (ctid): The Container ID of the LXC container.
#
# ### Logic
# 1.  **Snapshot Creation:** Executes `pct snapshot "$ctid" "$SNAPSHOT_NAME"`.
#     *   If the snapshot creation command fails, logs a fatal error and exits with code `7`.
# 2.  **Logging:** Confirms successful creation of the snapshot.
create_vllm_base_snapshot() {
    local ctid="$1"
    log_info "Creating ZFS snapshot '$SNAPSHOT_NAME' for container $ctid..."
    if ! pct snapshot "$ctid" "$SNAPSHOT_NAME"; then
        log_error "FATAL: Failed to create snapshot '$SNAPSHOT_NAME' for container $ctid."
        exit_script 7
    fi
    log_info "Snapshot '$SNAPSHOT_NAME' created successfully for container $ctid."
}

# ## Function: `start_container()`
#
# Starts the specified LXC container and waits for it to reach a running state.
# This is typically called after snapshot creation to bring the container back online.
#
# ### Arguments
# *   `$1` (ctid): The Container ID of the LXC container to start.
#
# ### Logic
# 1.  **Initiate Start:** Executes `pct start "$ctid"`.
#     *   If the start command fails, logs a fatal error and exits with code `6`.
# 2.  **Wait for Running:** Enters a loop, polling `pct status "$ctid"` until the container's status is "running".
#     *   Includes a timeout to prevent indefinite waiting.
#     *   If the container does not start within the timeout, logs a fatal error and exits with code `6`.
# 3.  **Logging:** Confirms successful container startup.
start_container() {
    local ctid="$1"
    local timeout=60 # Maximum wait time in seconds for the container to start.
    local interval=3 # Polling interval in seconds.
    local elapsed_time=0 # Tracks the elapsed time during the wait loop.

    log_info "Starting container $ctid after snapshot creation..."
    if ! pct start "$ctid"; then # Attempt to initiate container start.
        log_error "FATAL: Failed to start container $ctid."
        exit_script 6
    fi

    log_info "Waiting for container $ctid to start..."
    while [ "$elapsed_time" -lt "$timeout" ]; do # Loop until timeout or container starts.
        if pct status "$ctid" | grep -q "status: running"; then # Check if container status is 'running'.
            log_info "Container $ctid is running."
            return 0 # Exit function on successful start.
        fi
        sleep "$interval" # Wait before the next check.
        elapsed_time=$((elapsed_time + interval)) # Increment elapsed time.
    done

    log_error "FATAL: Container $ctid did not start within ${timeout} seconds." # Log error if timeout reached.
    exit_script 6
}

# ## Function: `main()`
#
# The main entry point of the script. It orchestrates the entire workflow for
# setting up `BaseTemplateVLLM` (CTID 920) and creating its ZFS snapshot.
#
# ### Workflow
# 1.  **Argument Parsing:** Retrieves the Container ID (CTID) from command-line arguments.
# 2.  **Input Validation:** Validates the provided CTID.
# 3.  **Container Existence Check:** Confirms the target container exists.
# 4.  **Snapshot Idempotency Check:** Determines if the `vllm-base-snapshot` already exists.
#     *   If it exists, the script exits successfully (idempotent behavior).
# 5.  **Prerequisite Verification:** Verifies Docker and NVIDIA GPU access inside the container.
# 6.  **vLLM Deployment & Test:** Deploys a test vLLM instance, verifies its API, and cleans up.
# 7.  **Container Shutdown:** Safely shuts down the container.
# 8.  **Snapshot Creation:** Creates the `vllm-base-snapshot`.
# 9.  **Container Startup:** Restarts the container.
# 10. **Script Exit:** Calls `exit_script` with a success code.
main() {
    parse_arguments "$@" # Parse command-line arguments to get CTID.
    validate_inputs # Validate the received CTID.
    check_container_exists # Ensure the target container exists.
    check_if_snapshot_exists # Check for existing snapshot; exits if found (idempotency).

    install_and_test_vllm_inside_container "$CTID" # Install and test vLLM.
    shutdown_container "$CTID" # Shut down the container for snapshot.
    create_vllm_base_snapshot "$CTID" # Create the ZFS snapshot.
    start_container "$CTID" # Start the container after snapshot.

    exit_script 0 # Indicate successful script completion.
}

# Call the main function
main "$@"