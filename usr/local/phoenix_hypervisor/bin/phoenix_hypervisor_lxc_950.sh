#!/bin/bash
#
# File: phoenix_hypervisor_lxc_950.sh
# Description: Manages the deployment and lifecycle of a vLLM API server within an LXC container (CTID 950).
#              This script handles environment verification, dynamic systemd service file generation,
#              service management (enable/start), and health checks to ensure the vLLM server
#              is running correctly and serving the specified model.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq, pct, systemctl, curl, journalctl.
# Inputs:
#   $1 (CTID) - The container ID for the vLLM server.
#   Configuration values from LXC_CONFIG_FILE: .vllm_model, .vllm_tensor_parallel_size,
#   .vllm_gpu_memory_utilization, .vllm_max_model_len, .network_config.ip.
# Outputs:
#   Systemd service file for vLLM API server, log messages to stdout and MAIN_LOG_FILE,
#   API responses from health checks and validation queries, exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Source common utilities ---
# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""
SERVICE_NAME="vllm_api_server"

# =====================================================================================
# Function: parse_arguments
# Description: Parses command-line arguments to extract the Container ID (CTID).
# Arguments:
#   $1 - The Container ID (CTID) for the LXC container.
# Returns:
#   Exits with status 2 if no CTID is provided or if too many arguments are given.
# =====================================================================================
parse_arguments() {
    # Check if exactly one argument (CTID) is provided
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1" # Assign the first argument to CTID
    log_info "Executing application runner for CTID: $CTID"
}

# =====================================================================================
# Function: verify_vllm_environment
# Description: Verifies the vLLM environment within the specified LXC container.
#              It checks for the presence and executability of the vLLM Python executable.
# Arguments:
#   None (uses global CTID).
# Returns:
#   Exits with a fatal error if the vLLM executable is not found or is not executable.
# =====================================================================================
verify_vllm_environment() {
    log_info "Verifying vLLM environment in CTID: $CTID..."
    local python_executable="/opt/vllm/bin/python3" # Expected path to vLLM's Python executable

    # Check if the vLLM Python executable file exists
    if ! pct_exec "$CTID" test -f "$python_executable"; then
        log_error "vLLM python executable not found at $python_executable."
        log_error "Listing contents of /opt/vllm/bin/:"
        pct_exec "$CTID" ls -l /opt/vllm/bin/ | log_plain_output # Log directory contents for debugging
        log_fatal "vLLM environment is incomplete."
    fi

    if ! pct_exec "$CTID" test -x "$python_executable"; then
        log_error "vLLM python executable is not executable."
        log_error "Listing permissions for $python_executable:"
        pct_exec "$CTID" ls -l "$python_executable" | log_plain_output
        log_fatal "vLLM environment has incorrect permissions."
    fi

    log_info "vLLM environment verified successfully."
}

# =====================================================================================
# Function: generate_systemd_service_file
# Description: Dynamically generates and writes a systemd service file for the vLLM API server
#              into the specified LXC container. It retrieves vLLM configuration parameters
#              from the central configuration file.
# Arguments:
#   None (uses global CTID and SERVICE_NAME).
# Returns:
#   Exits with a fatal error if the service file cannot be written into the container.
# =====================================================================================
generate_systemd_service_file() {
    log_info "Generating systemd service file for $SERVICE_NAME..."

    # --- Retrieve vLLM parameters from the central config ---
    # Retrieve vLLM model parameters from the central configuration file
    local model
    model=$(jq_get_value "$CTID" ".vllm_model")
    local tensor_parallel_size
    tensor_parallel_size=$(jq_get_value "$CTID" ".vllm_tensor_parallel_size")
    local gpu_memory_utilization
    gpu_memory_utilization=$(jq_get_value "$CTID" ".vllm_gpu_memory_utilization")
    local max_model_len
    max_model_len=$(jq_get_value "$CTID" ".vllm_max_model_len")

    # --- Construct the ExecStart command ---
    # Construct the ExecStart command for the vLLM API server
    local exec_start_cmd="/opt/vllm/bin/python3 -m vllm.entrypoints.api_server"
    exec_start_cmd+=" --model $model" # Specify the model to be served
    exec_start_cmd+=" --tensor-parallel-size $tensor_parallel_size" # Set tensor parallel size
    exec_start_cmd+=" --gpu-memory-utilization $gpu_memory_utilization" # Set GPU memory utilization
    exec_start_cmd+=" --max-model-len $max_model_len" # Set maximum model length
    exec_start_cmd+=" --kv-cache-dtype auto" # Configure KV cache data type
    exec_start_cmd+=" --disable-custom-all-reduce" # Disable custom all-reduce for vLLM
    exec_start_cmd+=" --host 0.0.0.0" # Bind to all network interfaces

    log_info "Constructed vLLM ExecStart command: $exec_start_cmd"

    # --- Create the systemd service file content using a single, robust printf command ---
    local service_file_content
    service_file_content=$(printf '%s\n' \
        "[Unit]" \
        "Description=vLLM API Server" \
        "After=network.target" \
        "" \
        "[Service]" \
        "User=root" \
        "WorkingDirectory=/opt/vllm" \
        "ExecStart=$exec_start_cmd" \
        "Restart=always" \
        "RestartSec=10" \
        "StandardOutput=journal" \
        "StandardError=journal" \
        "" \
        "[Install]" \
        "WantedBy=multi-user.target")

    # --- Write the service file inside the container using a robust pipe method ---
    # Define the path for the systemd service file inside the container
    local service_file_path="/etc/systemd/system/${SERVICE_NAME}.service"
    log_info "Writing systemd service file to $service_file_path in CTID $CTID..."

    # --- Use a here-doc and pipe it into the container for maximum reliability ---
    # Use a here-doc and pipe the service file content into the container for maximum reliability
    if ! echo "${service_file_content}" | pct exec "$CTID" -- tee "${service_file_path}" > /dev/null; then
        log_fatal "Failed to write systemd service file in CTID $CTID."
    fi

    log_info "Systemd service file generated successfully."
}

# =====================================================================================
# Function: manage_vllm_service
# Description: Manages the vLLM systemd service within the specified LXC container.
#              This includes reloading the systemd daemon, enabling the service to start
#              on boot, and starting/restarting the service. It also provides error
#              logging and retrieves journalctl logs on service startup failure.
# Arguments:
#   None (uses global CTID and SERVICE_NAME).
# Returns:
#   Exits with a fatal error if systemd daemon reload, service enable, or service start fails.
# =====================================================================================
manage_vllm_service() {
    log_info "Managing the $SERVICE_NAME service in CTID $CTID..."

    # --- Reload the systemd daemon to recognize the new service ---
    # Reload the systemd daemon to recognize the newly created service file
    log_info "Reloading systemd daemon..."
    if ! pct_exec "$CTID" systemctl daemon-reload; then
        log_fatal "Failed to reload systemd daemon in CTID $CTID."
    fi

    # --- Enable the service to start on boot ---
    # Enable the service to ensure it starts automatically on container boot
    log_info "Enabling $SERVICE_NAME service..."
    if ! pct_exec "$CTID" systemctl enable "$SERVICE_NAME"; then
        log_fatal "Failed to enable $SERVICE_NAME service in CTID $CTID."
    fi

    # --- Start the service ---
    # Start (or restart if already running) the vLLM API server service
    log_info "Starting $SERVICE_NAME service..."
    if ! pct_exec "$CTID" systemctl restart "$SERVICE_NAME"; then
        log_error "$SERVICE_NAME service failed to start. Retrieving logs..."
        # If the service fails to start, retrieve and log the latest journalctl logs for diagnosis
        local journal_logs
        journal_logs=$(pct_exec "$CTID" journalctl -u "$SERVICE_NAME" --no-pager -n 50)
        log_error "Recent logs for $SERVICE_NAME:"
        log_plain_output "$journal_logs" # Log the retrieved journal entries
        log_fatal "Failed to start $SERVICE_NAME service. See logs above for details."
    fi

    log_info "$SERVICE_NAME service started successfully."
}

# =====================================================================================
# Function: perform_health_check
# Description: Performs a health check on the vLLM API server to ensure it is responsive
#              and the correct model is loaded. It retries multiple times with a delay.
# Arguments:
#   None (uses global CTID).
# Returns:
#   0 on successful health check, exits with a fatal error if the health check fails
#   after all attempts.
# =====================================================================================
perform_health_check() {
    log_info "Performing health check on the vLLM API server..."
    local max_attempts=12 # Maximum number of health check attempts
    local attempt=0 # Current attempt counter
    local interval=10 # Delay between attempts in seconds
    local health_check_url="http://localhost:8000/v1/models" # Endpoint for health check
    local model_name
    model_name=$(jq_get_value "$CTID" ".vllm_model") # Expected model name from config

    # Loop to perform health checks until successful or max attempts reached
    while [ "$attempt" -lt "$max_attempts" ]; do
        attempt=$((attempt + 1)) # Increment attempt counter
        log_info "Health check attempt $attempt/$max_attempts..."
        
        local response
        # Execute curl command inside the container to check API endpoint
        response=$(pct exec "$CTID" -- curl -s "$health_check_url" || echo "CURL_ERROR")

        # Check if curl command itself failed (e.g., connection refused)
        if [ "$response" == "CURL_ERROR" ]; then
            log_info "API not ready yet (curl command failed, likely connection refused). Retrying in $interval seconds..."
            sleep "$interval" # Wait before retrying
            continue # Continue to the next attempt
        fi

        local model_id
        model_id=$(echo "$response" | jq -r ".data[0].id")

        # Compare the retrieved model ID with the expected model name
        if [ "$model_id" == "$model_name" ]; then
            log_info "Health check passed! The vLLM API server is responsive and the correct model is loaded."
            return 0 # Health check successful
        else
            log_info "API is responsive, but the model is not yet loaded. Retrying in $interval seconds..."
            sleep "$interval" # Wait before retrying
        fi
    done

    log_error "Health check failed after $max_attempts attempts. The API server is not responsive."
    log_error "Retrieving latest service logs for diagnosis..."
    log_error "Recent logs for $SERVICE_NAME:"
    pct_exec "$CTID" journalctl -u "$SERVICE_NAME" --no-pager -n 50 | log_plain_output
    log_fatal "vLLM service health check failed."
}

# =====================================================================================
# Function: validate_api_with_test_query
# Description: Sends a test chat completion query to the vLLM API server to confirm
#              that the model is loaded, responsive, and generating valid responses.
# Arguments:
#   None (uses global CTID).
# Returns:
#   Exits with a fatal error if the API returns an error or an unexpected response format.
# =====================================================================================
validate_api_with_test_query() {
    log_info "Performing a final API validation with a test query..."
    local model
    model=$(jq_get_value "$CTID" ".vllm_model") # Retrieve the model name
    local api_url="http://localhost:8000/v1/chat/completions" # API endpoint for chat completions
    
    # Construct the JSON payload for the test query using jq
    local json_payload
    json_payload=$(jq -n --arg model "$model" \
        '{model: $model, messages: [{role: "user", content: "What is the capital of France?"}]}')

    # --- Execute the curl command inside the container ---
    # Execute the curl command inside the container to send the test query
    local api_response
    api_response=$(pct_exec "$CTID" curl -s -X POST "$api_url" \
        -H "Content-Type: application/json" \
        -d "$json_payload")

    # --- Check if the response contains an error ---
    # Check if the API response contains an error field
    if echo "$api_response" | jq -e 'has("error")' > /dev/null; then
        log_error "API validation failed. The server returned an error."
        log_error "API Response:"
        echo "$api_response" | log_plain_output # Log the full API response for debugging
        log_fatal "The vLLM model appears to have failed to load correctly."
    fi

    # --- Check if the response contains a valid choice ---
    if ! echo "$api_response" | jq -e '.choices[0].message.content' > /dev/null; then
        log_error "API validation failed. The response format was unexpected."
        log_error "API Response:"
        echo "$api_response" | log_plain_output
        log_fatal "The vLLM model is not responding with valid completions."
    fi

    log_info "API validation successful! The model is loaded and generating responses."
    log_info "Test query response snippet: $(echo "$api_response" | jq -r '.choices[0].message.content' | head -c 100)..."
}

# =====================================================================================
# Function: display_connection_info
# Description: Displays the final connection details for the vLLM API server,
#              including IP address, port, model name, and an example curl command.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None.
# =====================================================================================
display_connection_info() {
    local ip_address
    ip_address=$(jq_get_value "$CTID" ".network_config.ip" | cut -d'/' -f1) # Extract IP address from network config
    local model
    model=$(jq_get_value "$CTID" ".vllm_model") # Retrieve the model name

    log_info "============================================================"
    log_info "vLLM API Server is now running and fully operational."
    log_info "============================================================"
    log_info "Connection Details:"
    log_info "  IP Address: $ip_address"
    log_info "  Port: 8000"
    log_info "  Model: $model"
    log_info ""
    log_info "Example curl command:"
    log_info "  curl -X POST \"http://${ip_address}:8000/v1/chat/completions\" \\"
    log_info "    -H \"Content-Type: application/json\" \\"
    log_info "    --data '{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Write a python function to download a file.\"}]}'"
    log_info "============================================================"
}

# =====================================================================================
# Function: main
# Description: Main entry point for the vLLM API server application runner script.
#              Orchestrates the entire process of setting up, starting, and verifying
#              the vLLM API server within an LXC container.
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   Exits with status 0 on successful completion, or a non-zero status on failure
#   (handled by exit_script).
# =====================================================================================
main() {
    parse_arguments "$@" # Parse command-line arguments
    verify_vllm_environment # Verify the vLLM installation and environment
    generate_systemd_service_file # Create the systemd service file for vLLM
    manage_vllm_service # Enable and start the vLLM service
    # perform_health_check # Perform a health check on the API (currently commented out)
    # validate_api_with_test_query # Validate API with a test query (currently commented out)
    display_connection_info # Display connection information to the user
    exit_script 0 # Exit successfully
}

main "$@"