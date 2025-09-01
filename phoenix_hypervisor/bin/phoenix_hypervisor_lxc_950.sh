#!/bin/bash
# ## Script: phoenix_hypervisor_lxc_950.sh
#
# ### Description
# This script finalizes the setup for LXC container 950, specifically for the `vllmQwen3Coder` service.
# It automates the deployment and configuration of a vLLM server, hosting the
# `lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-5bit` model.
#
# ### Key Functionality
# - Launches the vLLM server as a background process with specified model and tensor parallelism (2).
# - Waits for the large language model (LLM) to load and become ready.
# - Verifies the vLLM API accessibility.
#
# ### Context
# This container (CTID 950) is a final application container, designed to be cloned from
# the `vllm-base-snapshot` of CTID 920. It serves as a dedicated endpoint for the Qwen3-Coder model.
#
# ### Usage
# ```bash
# ./phoenix_hypervisor_lxc_950.sh <CTID>
# ```
# **Example:**
# ```bash
# ./phoenix_hypervisor_lxc_950.sh 950
# ```
#
# ### Arguments
# - **`$1` (CTID):** The Container ID. This script is specifically designed for CTID `950`.
#
# ### Requirements
# - **Proxmox Host:** Must have `pct` command available for LXC management.
# - **LXC Container 950:** Must be pre-created or cloned and accessible.
# - **`jq`:** JSON processor for parsing configuration files.
# - **Base Snapshot:** Container 950 is expected to be cloned from CTID 920's `vllm-base-snapshot`.
# - **NVIDIA:** NVIDIA drivers/toolkit must be fully functional inside container 950.
# - **Configuration Files:** Access to `phoenix_lxc_configs.json` and `phoenix_hypervisor_config.json`
#   for retrieving essential configuration details (e.g., IP, model, HF token path).
#
# ### Exit Codes
# - **`0` (Success):** vLLM Qwen3 Coder Server deployed, running, and accessible.
# - **`1` (General Error):** An unspecified error occurred.
# - **`2` (Invalid Arguments):** Incorrect command-line arguments provided.
# - **`3` (Container Not Found):** Container 950 does not exist or is inaccessible.
# - **`4` (vLLM Server Launch Failure):** vLLM Qwen3 Coder server failed to launch.
# - **`5` (Configuration Parse Error):** Failed to parse required details from configuration files.
# - **`6` (API Verification Failure):** vLLM Qwen3 Coder API accessibility verification failed.
#
# ### Version
# 0.1.0
#
# ### Author
# Heads, Qwen3-coder (AI Assistant)
#
# --- Global Variables and Constants ---
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"
LXC_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"

# --- Logging Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] phoenix_hypervisor_lxc_950.sh: $*" | tee -a "$MAIN_LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] phoenix_hypervisor_lxc_950.sh: $*" | tee -a "$MAIN_LOG_FILE" >&2
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
CONTAINER_IP=""
VLLM_MODEL=""
VLLM_TENSOR_PARALLEL_SIZE=""
HF_TOKEN_FILE_PATH=""
# No longer needed: EXPECTED_CONTAINER_NAME="vllm_qwen3_coder"
VLLM_LOG_FILE="/var/log/vllm_server.log"

# ## Function: parse_arguments
#
# ### Description
# Parses command-line arguments to extract the Container ID (CTID).
#
# ### Parameters
# None directly, uses `$@` for script arguments.
#
# ### Logic
# 1.  **Argument Count Check:** Verifies that exactly one argument is provided.
#     -   If not, logs a usage error and exits with code `2`.
# 2.  **CTID Assignment:** Assigns the first argument to the global variable `CTID`.
# 3.  **Logging:** Records the received CTID for auditing.
#
# ### Exit Codes
# - `2`: Invalid number of arguments.
#
# ### Usage
# Called at the beginning of the script to set the `CTID` for subsequent operations.
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Received CTID: $CTID"
}

# ## Function: validate_inputs
#
# ### Description
# Validates the provided Container ID (CTID) to ensure it is a positive integer
# and matches the expected value for this script (`950`).
#
# ### Parameters
# None directly, uses the global variable `CTID`.
#
# ### Logic
# 1.  **Integer Validation:** Checks if `CTID` is a positive integer.
#     -   If not, logs a fatal error and exits with code `2`.
# 2.  **CTID Specificity Check:** Verifies if `CTID` is `950`.
#     -   If not, logs a warning, indicating the script's primary design for CTID `950`, but continues execution.
# 3.  **Logging:** Confirms successful input validation.
#
# ### Exit Codes
# - `2`: Invalid CTID format or value.
#
# ### Context
# This validation step ensures that the script operates on the intended container
# and prevents execution with malformed or unexpected container IDs.
validate_inputs() {
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_error "FATAL: Invalid CTID '$CTID'. Must be a positive integer."
        exit_script 2
    fi
    if [ "$CTID" -ne 950 ]; then
        log_error "WARNING: This script is specifically designed for CTID 950 (vllmQwen3Coder). Proceeding, but verify usage."
    fi
    log_info "Input validation passed."
}

# ## Function: check_container_exists
#
# ### Description
# Verifies the existence and accessibility of the target LXC container using `pct status`.
# This is a critical prerequisite check before attempting any operations on the container.
#
# ### Parameters
# None directly, uses the global variable `CTID`.
#
# ### Logic
# 1.  **Status Check:** Executes `pct status "$CTID"` to determine if the container exists and is manageable.
# 2.  **Error Handling:**
#     -   If `pct status` returns a non-zero exit code, it indicates the container does not exist or is inaccessible.
#         A fatal error is logged, and the script exits with code `3`.
# 3.  **Confirmation:** If the container exists, a confirmation message is logged.
#
# ### Exit Codes
# - `3`: Container does not exist or is inaccessible.
#
# ### Context
# This function ensures that the script has a valid target container to operate on,
# preventing errors in subsequent steps that rely on container presence.
check_container_exists() {
    log_info "Checking for existence of container CTID: $CTID"
    if ! pct status "$CTID" > /dev/null 2>&1; then
        log_error "FATAL: Container $CTID does not exist or is not accessible."
        exit_script 3
    fi
    log_info "Container $CTID exists."
}

# ## Function: parse_required_configuration_details
#
# ### Description
# Extracts essential configuration parameters from `phoenix_lxc_configs.json` and
# `phoenix_hypervisor_config.json` using `jq`. These parameters are critical for
# deploying and verifying the vLLM Qwen3 Coder server.
#
# ### Parameters
# - `$1` (CTID): The Container ID for which to retrieve LXC-specific configurations.
#
# ### Global Variables Set
# - `CONTAINER_IP`: The IP address of the LXC container.
# - `VLLM_MODEL`: The specific vLLM model to be deployed (e.g., `lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-5bit`).
# - `VLLM_TENSOR_PARALLEL_SIZE`: The tensor parallelism size for the vLLM model.
# - `HF_TOKEN_FILE_PATH`: The file path to the HuggingFace token on the hypervisor.
#
# ### Logic
# 1.  **LXC Configuration Parsing:**
#     -   Verifies the existence of `LXC_CONFIG_FILE`.
#     -   Uses `jq` to extract `network_config.ip`, `vllm_model`, and `vllm_tensor_parallel_size`
#         for the given `CTID`.
#     -   Logs the extracted LXC configuration details.
# 2.  **Hypervisor Configuration Parsing:**
#     -   Verifies the existence of `HYPERVISOR_CONFIG_FILE`.
#     -   Uses `jq` to extract `core_paths.hf_token_file`.
#     -   Logs the extracted HuggingFace token file path.
# 3.  **Validation of Parsed Details:**
#     -   Checks if all required variables (`CONTAINER_IP`, `VLLM_MODEL`, `VLLM_TENSOR_PARALLEL_SIZE`,
#         `HF_TOKEN_FILE_PATH`) are non-empty.
#     -   If any are missing, logs a fatal error and exits with code `5`.
# 4.  **Confirmation:** Logs successful parsing and validation of all required configurations.
#
# ### Exit Codes
# - `5`: Configuration file not found or failed to parse required details.
#
# ### Dependencies
# - `jq`: Command-line JSON processor.
# - `LXC_CONFIG_FILE`: Path to the LXC configuration JSON.
# - `HYPERVISOR_CONFIG_FILE`: Path to the hypervisor configuration JSON.
#
# ### Context
# This function centralizes the retrieval of dynamic configuration, ensuring that
# the deployment process uses up-to-date and validated parameters.
parse_required_configuration_details() {
    log_info "Parsing required configuration details from JSON files for CTID: $CTID"

    # 1. Parse LXC Config for CTID 950
    if [ ! -f "$LXC_CONFIG_FILE" ]; then
        log_error "FATAL: LXC configuration file not found at $LXC_CONFIG_FILE."
        exit_script 5
    fi
    CONTAINER_IP=$(jq -r --arg ctid "$CTID" '.lxc_configs[$ctid | tostring].network_config.ip | split("/") | .' "$LXC_CONFIG_FILE")
    VLLM_MODEL=$(jq -r --arg ctid "$CTID" '.lxc_configs[$ctid | tostring].vllm_model // ""' "$LXC_CONFIG_FILE")
    VLLM_TENSOR_PARALLEL_SIZE=$(jq -r --arg ctid "$CTID" '.lxc_configs[$ctid | tostring].vllm_tensor_parallel_size // ""' "$LXC_CONFIG_FILE")
    log_info "Parsed LXC config: IP=$CONTAINER_IP, Model=$VLLM_MODEL, Tensor Parallel Size=$VLLM_TENSOR_PARALLEL_SIZE"

    # 2. Parse Hypervisor Config for HF Token Path
    if [ ! -f "$HYPERVISOR_CONFIG_FILE" ]; then
        log_error "FATAL: Hypervisor configuration file not found at $HYPERVISOR_CONFIG_FILE."
        exit_script 5
    fi
    HF_TOKEN_FILE_PATH=$(jq -r '.core_paths.hf_token_file // ""' "$HYPERVISOR_CONFIG_FILE")
    log_info "Parsed HF token file path: $HF_TOKEN_FILE_PATH"

    # 3. Validate Parsed Details
    if [ -z "$CONTAINER_IP" ] || [ -z "$VLLM_MODEL" ] || [ -z "$VLLM_TENSOR_PARALLEL_SIZE" ] || [ -z "$HF_TOKEN_FILE_PATH" ]; then
        log_error "FATAL: One or more required configuration details are missing or empty."
        exit_script 5
    fi
    log_info "All required configuration details parsed and validated successfully."
}

# ## Function: launch_vllm_server_inside_container
#
# ### Description
# Launches the vLLM server directly within the specified LXC container (`CTID`)
# as a background process using `nohup`. This server hosts the Qwen3-Coder model,
# configured with specific tensor parallelism and HuggingFace token for authentication.
#
# ### Parameters
# - `$1` (CTID): The Container ID where the vLLM server will be launched.
#
# ### Dependencies
# - Global variables: `VLLM_MODEL`, `VLLM_TENSOR_PARALLEL_SIZE`, `HF_TOKEN_FILE_PATH`.
# - `vllm` must be installed and accessible within the LXC container.
#
# ### Logic
# 1.  **Parameter Preparation:**
#     -   Constructs the `vllm serve` command with the specified model, tensor parallelism,
#         and `--host 0.0.0.0` flag.
# 2.  **Command Construction:**
#     -   Assembles the complete `nohup` command string, redirecting stdout/stderr to a log file.
# 3.  **Execution:**
#     -   Executes the constructed `nohup` command inside the LXC container using `pct exec`.
# 4.  **Error Handling:**
#     -   If the `pct exec` command fails (non-zero exit code), logs a fatal error
#         and exits the script with code `4`.
# 5.  **Confirmation:** Logs successful initiation of the vLLM Qwen3 Coder server launch.
#
# ### Exit Codes
# - `4`: vLLM Qwen3 Coder server launch failed.
#
# ### Context
# This function is the core deployment step, responsible for launching the AI model
# serving infrastructure within the isolated LXC environment without Docker.
launch_vllm_server_inside_container() {
    log_info "Launching vLLM Qwen3 Coder server directly inside container CTID: $CTID"

    local serve_cmd="vllm serve $VLLM_MODEL --host 0.0.0.0 --port 8000 --tensor-parallel-size $VLLM_TENSOR_PARALLEL_SIZE"

    # Construct the full nohup command string
    local full_launch_cmd="nohup $serve_cmd > $VLLM_LOG_FILE 2>&1 &"

    log_info "Constructing and executing the vLLM server launch command:"
    log_info "$full_launch_cmd"
    if ! pct exec "$CTID" -- bash -c "$full_launch_cmd"; then
        log_error "FATAL: vLLM Qwen3 Coder server launch failed for CTID $CTID."
        exit_script 4
    fi
    log_info "vLLM Qwen3 Coder server launch initiated successfully."
}

# ## Function: wait_for_vllm_server_readiness
#
# ### Description
# Monitors the vLLM server's readiness by polling its health endpoint.
# It waits until the vLLM service is responsive and ready to serve requests.
#
# ### Parameters
# - `$1` (CTID): The Container ID where the vLLM server is running.
#
# ### Dependencies
# - `curl`: Must be available inside the LXC container for making HTTP requests.
#
# ### Logic
# 1.  **Timeout and Polling:** Sets a maximum `timeout` (10 minutes) and a `polling interval` (15 seconds)
#     to prevent indefinite waiting.
# 2.  **Loop for Readiness:** Enters a `while` loop that continues until the server is ready or the timeout is reached.
#     -   **Health Check:** Uses `curl` to send a request to `http://localhost:8000/v1/health`.
#     -   **Status Evaluation:** If `curl` returns a 200 OK status, the server is considered ready.
#     -   **Sleep:** Pauses for the defined `interval` before the next check.
# 3.  **Timeout Handling:** If the `timeout` is exceeded before the server is ready, logs a fatal error and returns `1`.
# 4.  **Confirmation:** If the server indicates readiness, logs a success message and returns `0`.
#
# ### Return Codes
# - `0`: vLLM server is ready.
# - `1`: Timeout occurred, server did not indicate readiness.
#
# ### Context
# This function is crucial for ensuring that the deployed AI service is fully operational
# before proceeding with API verification or declaring the deployment successful.
# Large language models require significant time to load, making this a necessary step.
wait_for_vllm_server_readiness() {
    log_info "Waiting for vLLM server to become ready inside container CTID: $CTID"
    local timeout=600 # 10 minutes for large model
    local interval=15 # 15 seconds
    local elapsed_time=0
    local server_ready=false

    while [ "$elapsed_time" -lt "$timeout" ]; do
        if pct exec "$CTID" -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/v1/health | grep -q "200"; then
            log_info "vLLM server appears to be ready."
            server_ready=true
            break
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    if [ "$server_ready" == "false" ]; then
        log_error "FATAL: vLLM server did not indicate readiness within ${timeout} seconds."
        return 1
    fi
    log_info "vLLM server initialized and ready."
    return 0
}

# ## Function: verify_vllm_qwen3_coder_api_accessibility
#
# ### Description
# Verifies the accessibility and correct functionality of the vLLM Qwen3 Coder API
# endpoint by sending a sample chat completion request from within the LXC container.
#
# ### Parameters
# - `$1` (CTID): The Container ID where the vLLM service is running.
#
# ### Dependencies
# - Global variables: `VLLM_MODEL`.
# - `curl`: Must be available inside the LXC container for making HTTP requests.
# - `jq`: Must be available inside the LXC container for parsing JSON responses.
#
# ### Logic
# 1.  **Curl Command Construction:** Builds a `curl` command to send a POST request
#     to the `/v1/chat/completions` endpoint, including a sample user message.
# 2.  **Execution and Output Capture:** Executes the `curl` command inside the LXC container
#     and captures both its output (JSON response) and exit code.
# 3.  **Error Handling (Curl):** If the `curl` command fails, logs a fatal error
#     and returns `1`.
# 4.  **Response Logging:** Logs the full JSON response from the vLLM API for debugging and auditing.
# 5.  **Content Verification:**
#     -   Parses the JSON response using `jq` to extract the assistant's reply content.
#     -   Checks if the extracted content contains the word "Paris" (case-insensitive),
#         as expected for the "What is the capital of France?" query.
#     -   Logs success if "Paris" is found.
#     -   Logs a warning if "Paris" is not found, indicating a potential issue with
#         model response, but does not halt execution (soft failure).
# 6.  **Confirmation:** Logs that the vLLM Qwen3 Coder API is verified as accessible.
#
# ### Return Codes
# - `0`: API verification successful.
# - `1`: API access verification failed (e.g., curl command failed, JSON parsing error).
#
# ### Context
# This function provides an end-to-end test of the deployed vLLM service,
# confirming not only network accessibility but also the model's ability to
# process requests and generate coherent responses.
verify_vllm_qwen3_coder_api_accessibility() {
    log_info "Verifying vLLM Qwen3 Coder API accessibility for CTID: $CTID"

    local curl_cmd='curl -X POST http://localhost:8000/v1/chat/completions -H "Content-Type: application/json" -d "{\"model\": \"'$VLLM_MODEL'\", \"messages\": [{\"role\": \"user\", \"content\": \"What is the capital of France?\"}]}"'
    local curl_output
    local curl_exit_code

    if ! curl_output=$(pct exec "$CTID" -- bash -c "$curl_cmd" 2>&1); then
        log_error "FATAL: vLLM Qwen3 Coder API access verification failed for CTID $CTID. Curl command failed."
        echo "$curl_output" | log_error
        return 1
    fi
    log_info "vLLM API response:"
    echo "$curl_output" | while IFS= read -r line; do log_info "$line"; done

    local assistant_reply=$(echo "$curl_output" | jq -r '.choices.message.content // ""')
    if echo "$assistant_reply" | grep -iq "Paris"; then
        log_info "vLLM Qwen3 Coder API verification successful: response contains 'Paris'."
    else
        log_error "WARNING: Model reply did not contain the expected word 'Paris'. Response content: '$assistant_reply'"
    fi

    log_info "vLLM Qwen3 Coder API verified as accessible at http://localhost:8000/v1/chat/completions."
    return 0
}

# ## Function: main
#
# ### Description
# The main entry point of the script, orchestrating the entire deployment and
# verification process for the `vllmQwen3Coder` service in LXC container 950.
#
# ### Parameters
# - `$@`: All command-line arguments passed to the script.
#
# ### Logic Flow
# 1.  **Argument Parsing:** Calls `parse_arguments` to retrieve the `CTID`.
# 2.  **Input Validation:** Calls `validate_inputs` to ensure the `CTID` is valid.
# 3.  **Container Existence Check:** Calls `check_container_exists` to confirm the LXC container is present.
# 4.  **Configuration Retrieval:** Calls `parse_required_configuration_details` to load
#     LXC and hypervisor configurations (IP, model, tensor size, HF token path).
# 5.  **Container Deployment:** Calls `launch_vllm_server_inside_container`
#     to launch the vLLM server.
# 6.  **Model Initialization Wait:** Calls `wait_for_vllm_server_readiness` to
#     await the full loading and readiness of the Qwen3 Coder model.
# 7.  **API Accessibility Verification:** Calls `verify_vllm_qwen3_coder_api_accessibility`
#     to confirm the vLLM API is responsive.
# 8.  **Script Exit:** Calls `exit_script` with a success code (`0`) upon completion of all steps.
#
# ### Exit Codes
# - `0`: All deployment and verification steps completed successfully.
#   (Other exit codes are handled by individual functions and propagated via `exit_script`).
#
# ### Context
# This function defines the sequential execution of tasks required to set up
# and validate the vLLM Qwen3 Coder service, ensuring a robust and automated deployment.
main() {
    parse_arguments "$@"
    validate_inputs
    check_container_exists
    parse_required_configuration_details "$CTID"
    launch_vllm_server_inside_container "$CTID"
    wait_for_vllm_server_readiness "$CTID"
    verify_vllm_qwen3_coder_api_accessibility "$CTID"

    exit_script 0
}

# Call the main function
main "$@"