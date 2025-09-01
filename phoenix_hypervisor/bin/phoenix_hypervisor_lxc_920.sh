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

# ## Function: `verify_prerequisites_inside_container()`
#
# Confirms that Docker Engine and the NVIDIA Container Toolkit are correctly installed
# and functional within the target LXC container. This is crucial before attempting vLLM deployment.
#
# ### Arguments
# *   `$1` (ctid): The Container ID of the LXC container.
#
# ### Logic
# 1.  **Docker Info Verification:**
#     *   Executes `docker info` inside the container to check Docker's operational status and confirm
#         the presence of the NVIDIA runtime.
#     *   Captures and logs the output for detailed inspection.
#     *   If the command fails, logs a fatal error and exits with code `4`.
# 2.  **NVIDIA GPU Access Verification:**
#     *   Executes `nvidia-smi` inside the container to verify direct GPU access and driver functionality.
#     *   Captures and logs the output.
#     *   If the command fails, logs a fatal error and exits with code `4`.
# 3.  **Logging:** Confirms successful verification of all prerequisites.
verify_prerequisites_inside_container() {
    local ctid="$1"
    log_info "Verifying prerequisites (Docker, NVIDIA) inside container CTID: $ctid."

    # ### 1. Verify Docker Info (including NVIDIA Runtime)
    log_info "Verifying Docker information inside CTID $ctid..."
    local docker_info_output
    if ! docker_info_output=$(pct exec "$ctid" -- docker info 2>&1); then
        log_error "FATAL: Docker verification failed for CTID $ctid. 'docker info' command failed."
        echo "$docker_info_output" | log_error
        exit_script 4
    fi
    log_info "Docker information verified inside CTID $ctid. Docker info output:"
    echo "$docker_info_output" | while IFS= read -r line; do log_info "$line"; done

    # ### 2. Verify Direct GPU Access
    log_info "Verifying direct GPU access by running `nvidia-smi` inside CTID $ctid..."
    local nvidia_smi_output
    if ! nvidia_smi_output=$(pct exec "$ctid" -- nvidia-smi 2>&1); then
        log_error "FATAL: Direct GPU access verification failed for CTID $ctid. 'nvidia-smi' command failed."
        echo "$nvidia_smi_output" | log_error
        exit_script 4
    fi
    log_info "Direct GPU access verified inside CTID $ctid. `nvidia-smi` output:"
    echo "$nvidia_smi_output" | while IFS= read -r line; do log_info "$line"; done

    log_info "All prerequisites verified successfully inside container CTID: $ctid."
}

# ## Function: `deploy_and_test_vllm_inside_container()`
#
# Orchestrates the deployment of a test vLLM container, verifies its API functionality,
# and ensures proper cleanup. This function is critical for validating the `BaseTemplateVLLM` setup.
#
# ### Arguments
# *   `$1` (ctid): The Container ID of the LXC container.
#
# ### Logic
# 1.  **Pull vLLM Docker Image:** Downloads the official `vllm/vllm-openai:latest` Docker image.
#     *   If the pull fails, logs a fatal error and exits with code `5`.
# 2.  **Run Test vLLM Container:** Starts a detached Docker container running vLLM with a specified
#     test model (`Qwen/Qwen2.5-Coder-0.5B-Instruct-GPTQ-Int8`).
#     *   Configures GPU access, port mapping, and IPC host mode.
#     *   If the container fails to start, logs a fatal error and exits with code `5`.
# 3.  **Wait for Model Load:** Polls the Docker container logs, waiting for an indication that the
#     vLLM server is running (e.g., "Uvicorn running on").
#     *   Includes a timeout mechanism to prevent indefinite waiting.
#     *   Logs a warning if the model does not indicate readiness within the timeout.
# 4.  **Verify API Access via Curl:** Sends a chat completion request to the vLLM API using `curl`.
#     *   Checks the JSON response for the expected word "Paris" to confirm basic functionality.
#     *   If the `curl` command fails, logs a fatal error, attempts cleanup, and exits with code `5`.
#     *   Logs a warning if "Paris" is not found, as model responses can vary.
# 5.  **Clean Up Test Container:** Stops and removes the temporary vLLM test container.
#     *   Uses the `clean_up_test_container` helper function for this purpose.
#
# ### Dependencies
# *   `clean_up_test_container()`: Helper function for stopping and removing the Docker container.
deploy_and_test_vllm_inside_container() {
    local ctid="$1"
    log_info "Starting vLLM test deployment and verification inside container CTID: $ctid"

    local vllm_image="vllm/vllm-openai:latest" # Official vLLM Docker image.
    local test_model="Qwen/Qwen2.5-Coder-0.5B-Instruct-GPTQ-Int8" # Small model for testing, as discussed in requirements.
    local test_container_name="vllm_test_container" # Name for the temporary test container.

    # ### 1. Pull Official vLLM Docker Image
    log_info "Pulling official vLLM Docker image: $vllm_image..."
    if ! pct exec "$ctid" -- docker pull "$vllm_image"; then
        log_error "FATAL: Failed to pull vLLM Docker image for CTID $ctid."
        exit_script 5
    fi
    log_info "vLLM image pulled successfully for CTID $ctid."

    # ### 2. Run Test vLLM Container
    log_info "Running test vLLM container: $test_container_name with model $test_model inside CTID $ctid..."
    local run_opts="--runtime nvidia --gpus all -p 8000:8000 --ipc=host --name $test_container_name" # Docker run options for GPU access and port mapping.
    local model_arg="--model $test_model" # Argument to specify the model for vLLM.
    local full_run_cmd="docker run -d $run_opts $vllm_image $model_arg" # Complete Docker run command.

    if ! pct exec "$ctid" -- $full_run_cmd; then
        log_error "FATAL: Failed to start test vLLM container '$test_container_name' for CTID $ctid."
        exit_script 5
    fi
    log_info "Test vLLM container '$test_container_name' started for CTID $ctid."

    # ### 3. Wait for Model Load
    log_info "Waiting for test model to load inside CTID $ctid..."
    local timeout=300 # Maximum wait time in seconds (5 minutes) for the model to load.
    local interval=10 # Polling interval in seconds.
    local elapsed_time=0 # Tracks the elapsed time during the wait loop.
    local model_ready=false # Flag to indicate if the model has reported readiness.

    while [ "$elapsed_time" -lt "$timeout" ]; do # Loop until timeout or model readiness.
        # Check Docker logs for the "Uvicorn running on" message, indicating the vLLM server is active.
        if pct exec "$ctid" -- docker logs "$test_container_name" 2>&1 | grep -q "Uvicorn running on"; then
            log_info "vLLM model/server appears to be ready inside CTID $ctid."
            model_ready=true
            break # Exit loop if ready.
        fi
        sleep "$interval" # Wait before the next check.
        elapsed_time=$((elapsed_time + interval)) # Increment elapsed time.
    done

    if [ "$model_ready" == "false" ]; then # Check if the model was ready within the timeout.
        log_error "WARNING: vLLM model did not indicate readiness within ${timeout} seconds for CTID $ctid. Proceeding to API test, but this may indicate an issue."
    else
        log_info "vLLM model load wait completed for CTID $ctid."
    fi

    # ### 4. Verify API Access via Curl (Check for 'Paris')
    log_info "Verifying vLLM API access via curl inside CTID $ctid..."
    # Construct the curl command to query the vLLM OpenAI-compatible API.
    local curl_cmd='curl -X POST http://localhost:8000/v1/chat/completions -H "Content-Type: application/json" -d "{\"model\": \"'$test_model'\", \"messages\": [{\"role\": \"user\", \"content\": \"What is the capital of France?\"}]}"'
    local curl_output # Stores the raw output from the curl command.
    local curl_exit_code # Stores the exit code of the curl command.

    # Execute the curl command inside the container.
    if ! curl_output=$(pct exec "$ctid" -- bash -c "$curl_cmd" 2>&1); then
        log_error "FATAL: vLLM API access verification failed for CTID $ctid. Curl command failed."
        echo "$curl_output" | log_error
        clean_up_test_container "$ctid" "$test_container_name" # Attempt cleanup before exiting on failure.
        exit_script 5
    fi
    log_info "vLLM API response for CTID $ctid:"
    echo "$curl_output" | while IFS= read -r line; do log_info "$line"; done

    # Extract the assistant's reply content from the JSON response using `jq`.
    local assistant_reply=$(echo "$curl_output" | jq -r '.choices.message.content // ""')
    if echo "$assistant_reply" | grep -iq "Paris"; then # Case-insensitive search for "Paris".
        log_info "vLLM API verification successful for CTID $ctid: response contains 'Paris'."
    else
        log_error "WARNING: Model reply for CTID $ctid did not contain the expected word 'Paris'. Response content: '$assistant_reply'"
        # This is a warning, not a fatal error, as the model might respond differently but still be functional.
    fi
    # Note: If jq parsing fails, assistant_reply will be empty, and the grep will not find "Paris".

    # ### 5. Clean Up Test Container
    clean_up_test_container "$ctid" "$test_container_name"

    log_info "vLLM test deployment and verification completed successfully inside container CTID: $ctid."
}

# ## Function: `clean_up_test_container()`
#
# A helper function to stop and remove a specified Docker container within an LXC container.
# This ensures that temporary test containers do not persist after script execution.
#
# ### Arguments
# *   `$1` (ctid): The Container ID of the LXC container.
# *   `$2` (container_name): The name of the Docker container to stop and remove.
#
# ### Logic
# 1.  **Stop Container:** Attempts to stop the Docker container using `docker stop`.
#     *   Logs a warning if stopping fails, but continues to attempt removal.
# 2.  **Remove Container:** Attempts to remove the Docker container using `docker rm`.
#     *   Logs a warning if removal fails.
clean_up_test_container() {
    local ctid="$1"
    local container_name="$2"
    log_info "Stopping and removing test vLLM container '$container_name' inside CTID $ctid..."
    if pct exec "$ctid" -- docker stop "$container_name"; then
        log_info "Test container '$container_name' stopped successfully."
    else
        log_error "WARNING: Failed to stop test container '$container_name' inside CTID $ctid."
    fi
    if pct exec "$ctid" -- docker rm "$container_name"; then
        log_info "Test container '$container_name' removed successfully."
    else
        log_error "WARNING: Failed to remove test container '$container_name' inside CTID $ctid."
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

    verify_prerequisites_inside_container "$CTID" # Verify Docker and NVIDIA setup.
    deploy_and_test_vllm_inside_container "$CTID" # Deploy and test vLLM.
    shutdown_container "$CTID" # Shut down the container for snapshot.
    create_vllm_base_snapshot "$CTID" # Create the ZFS snapshot.
    start_container "$CTID" # Start the container after snapshot.

    exit_script 0 # Indicate successful script completion.
}

# Call the main function
main "$@"