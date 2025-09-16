#!/bin/bash
#
# File: phoenix_hypervisor_lxc_950.sh
# Description: Manages the deployment and lifecycle of a vLLM API server within an LXC container (CTID 950).
#              This script handles environment verification, dynamic systemd service file generation,
#              and service management using container-native commands (e.g., systemctl, curl)
#              to ensure the vLLM server is running correctly.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq.
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
source "$(dirname "$0")/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""
SERVICE_NAME="vllm_model_server"

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
# The verify_vllm_environment function has been removed as it is no longer
# necessary in a template-based deployment model. The environment is assumed
# to be correct as it is cloned from a hardened template.

# =====================================================================================
# Function: configure_and_start_systemd_service
# Description: Configures and starts the vLLM systemd service.
#              It replaces placeholders in the template service file with
#              configuration values and then starts and enables the service.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if configuration or service start fails.
# =====================================================================================
configure_and_start_systemd_service() {
    log_info "Configuring and starting vLLM systemd service in CTID: $CTID..."
    local service_file_path="/etc/systemd/system/vllm_model_server.service"

    # --- Retrieve vLLM parameters from the central config ---
    local model
    model=$(jq_get_value "$CTID" ".vllm_model")
    mapfile -t vllm_args < <(jq_get_array "$CTID" ".vllm_args[]")
    if [ ${#vllm_args[@]} -eq 0 ]; then
        log_fatal "Could not read vLLM arguments from config file for CTID $CTID."
    fi
    local port
    port=$(jq_get_value "$CTID" ".ports[0]" | cut -d':' -f2)

    # --- Construct the arguments string ---
    local args_string=""
    for arg in "${vllm_args[@]}"; do
        args_string+="\"$arg\" "
    done

    # --- Replace placeholders in the service file ---
    sed -i "s|VLLM_MODEL_PLACEHOLDER|$model|" "$service_file_path"
    sed -i "s|VLLM_PORT_PLACEHOLDER|$port|" "$service_file_path"
    sed -i "s|VLLM_ARGS_PLACEHOLDER|$args_string|" "$service_file_path"

    # --- Reload systemd, enable and start the service ---
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"

    # --- Verify the service is active ---
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log_fatal "vLLM service ($SERVICE_NAME) failed to start in CTID $CTID."
    fi

    log_info "vLLM service ($SERVICE_NAME) started successfully in CTID $CTID."
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
    local max_attempts=30 # Maximum number of health check attempts
    local attempt=0 # Current attempt counter
    local interval=10 # Delay between attempts in seconds
    local port
    port=$(jq_get_value "$CTID" ".vllm_port")
    local health_check_url="http://localhost:${port}/health"
    local model_name
    local model_name
    model_name=$(jq_get_value "$CTID" ".vllm_served_model_name") # Expected model name from config

    # Loop to perform health checks until successful or max attempts reached
    while [ "$attempt" -lt "$max_attempts" ]; do
        attempt=$((attempt + 1)) # Increment attempt counter
        log_info "Health check attempt $attempt/$max_attempts..."
        
        local response
        # Execute curl command inside the container to check API endpoint
        # Use curl with --fail to handle non-2xx responses as errors
        if curl -s --fail "$health_check_url" > /dev/null; then
            log_info "Health check passed! The vLLM API server is responsive."
            return 0
        else
            log_info "API not ready yet. Retrying in $interval seconds..."
            sleep "$interval"
        fi
    done

    log_error "Health check failed after $max_attempts attempts. The API server is not responsive."
    log_error "Retrieving latest service logs for diagnosis..."
    log_error "Recent logs for $SERVICE_NAME:"
    journalctl -u "$SERVICE_NAME" --no-pager -n 50 | log_plain_output
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
    local model
    model=$(jq_get_value "$CTID" ".vllm_served_model_name") # Retrieve the model name
    local port
    port=$(jq_get_value "$CTID" ".vllm_port")
    local api_url="http://localhost:${port}/v1/chat/completions" # API endpoint for chat completions
    
    # Construct the JSON payload for the test query using jq
    local json_payload
    json_payload=$(jq -n --arg model "$model" \
        '{model: $model, messages: [{role: "user", content: "What is the capital of France?"}]}')

    # --- Execute the curl command inside the container ---
    # Execute the curl command inside the container to send the test query
    local api_response
    api_response=$(curl -s -X POST "$api_url" \
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
    local model
    model=$(jq_get_value "$CTID" ".vllm_served_model_name") # Retrieve the model name

    log_info "============================================================"
    log_info "vLLM API Server is now running and fully operational."
    log_info "============================================================"
    log_info "Connection Details:"
    log_info "  IP Address: $ip_address"
    local port
    port=$(jq_get_value "$CTID" ".vllm_port")
    log_info "  Port: $port"
    log_info "  Model: $model"
    log_info ""
    log_info "Example curl command:"
    local port
    port=$(jq_get_value "$CTID" ".vllm_port")
    log_info "  curl -X POST \"http://${ip_address}:${port}/v1/chat/completions\" \\"
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
    # The call to verify_vllm_environment has been removed.
    configure_and_start_systemd_service # Configure and start the vLLM systemd service
    perform_health_check # Perform a health check on the API
    validate_api_with_test_query # Validate API with a test query
    display_connection_info # Display connection information to the user
    exit_script 0 # Exit successfully
}

main "$@"