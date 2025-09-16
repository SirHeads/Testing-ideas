#!/bin/bash
#
# File: phoenix_hypervisor_lxc_951.sh
# Description: Manages the deployment and lifecycle of a vLLM API server within an LXC container (CTID 951).
#              This script handles environment verification, dynamic systemd service file generation,
#              service management (enable/start), and health checks to ensure the vLLM server
#              is running correctly and serving the specified model for embeddings.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq, systemctl, curl, journalctl.
#               Note: This script is executed inside the container and must not use host-level
#               commands like 'pct' or 'qm'.
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
SERVICE_NAME="embedding_api_server"
VLLM_SERVICE_NAME="vllm_model_server"

# =====================================================================================
# Function: parse_arguments
# Description: Parses the CTID from command-line arguments.
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Executing application runner for CTID: $CTID"
}

# =====================================================================================
# Function: generate_vllm_service_file
# Description: Dynamically creates a systemd service file for the vLLM model server
#              by reading configuration directly from the JSON file.
# =====================================================================================
generate_vllm_service_file() {
    log_info "Generating systemd service file for $VLLM_SERVICE_NAME..."

    # Retrieve core configuration values
    local model=$(jq_get_value "$CTID" ".vllm_model")
    
    # Read the vllm_args array into a bash array
    mapfile -t vllm_args < <(jq_get_array "$CTID" ".vllm_args[]")
    if [ ${#vllm_args[@]} -eq 0 ]; then
        log_fatal "Could not read vLLM arguments from config file for CTID $CTID."
    fi

    # Construct the ExecStart command from the array
    local exec_start_cmd="/opt/vllm/bin/vllm serve \"$model\""
    for arg in "${vllm_args[@]}"; do
        exec_start_cmd+=" $arg"
    done

    local service_file_path="/etc/systemd/system/${VLLM_SERVICE_NAME}.service"
    log_info "Writing systemd service file to $service_file_path in CTID $CTID..."

    # Use a heredoc to write the service file, now with a data-driven ExecStart
    if ! bash -c "cat > ${service_file_path}" <<EOF; then
[Unit]
Description=vLLM OpenAI-Compatible Model Server
After=network.target

[Service]
User=root
ExecStart=$exec_start_cmd --host 0.0.0.0 --port $(jq_get_value "$CTID" ".ports[0]" | cut -d':' -f2)
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        log_fatal "Failed to write vLLM systemd service file in CTID $CTID."
    fi

    log_info "vLLM systemd service file generated successfully."
}

# =====================================================================================
# Function: manage_vllm_service
# Description: Enables and starts the vLLM model server systemd service.
# =====================================================================================
manage_vllm_service() {
    log_info "Managing the $VLLM_SERVICE_NAME service in CTID $CTID..."

    # --- Reload, enable, and restart the vLLM service ---
    systemctl daemon-reload
    systemctl enable "$VLLM_SERVICE_NAME"
    if ! systemctl restart "$VLLM_SERVICE_NAME"; then
        log_error "$VLLM_SERVICE_NAME service failed to start. Retrieving logs..."
        journalctl -u "$VLLM_SERVICE_NAME" --no-pager -n 50 | log_plain_output
        log_fatal "Failed to start $VLLM_SERVICE_NAME service."
    fi

    log_info "$VLLM_SERVICE_NAME service started successfully."
}

# =====================================================================================
# Function: perform_health_check
# Description: Performs a health check to ensure the vLLM API is responsive.
# =====================================================================================
perform_health_check() {
    log_info "Performing health check on the vLLM API server..."
    local max_attempts=10
    local attempt=0
    local interval=10 # seconds
    local health_check_url="http://localhost:8000/health"

    while [ "$attempt" -lt "$max_attempts" ]; do
        attempt=$((attempt + 1))
        log_info "Health check attempt $attempt/$max_attempts..."
        
        # Use curl's --fail option to handle HTTP errors and connection issues
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
    log_error "Recent logs for $VLLM_SERVICE_NAME:"
    journalctl -u "$VLLM_SERVICE_NAME" --no-pager -n 50 | log_plain_output
    log_fatal "vLLM service health check failed."
}

# =====================================================================================
# Function: validate_api_with_test_query
# Description: Sends a test query to the API to confirm the model is loaded and working for embeddings.
# =====================================================================================
validate_api_with_test_query() {
    log_info "Performing a final API validation with a test query for embeddings..."
    local model
    model=$(jq_get_value "$CTID" ".vllm_model")
    local api_url="http://localhost:8000/v1/embeddings"
    
    # --- Construct the JSON payload for the test query (compact format) ---
    local json_payload
    json_payload=$(jq -c -n --arg model "$model" \
        '{"model": $model, "input": "This is a test sentence for embedding."}')

    # --- Execute the curl command inside the container using bash -c for robust quoting ---
    local api_response
    local curl_cmd="curl -s -X POST '$api_url' -H 'Content-Type: application/json' -d '$json_payload'"
    log_info "Executing in CTID $CTID via bash: $curl_cmd"
    api_response=$(bash -c "$curl_cmd")

    # --- Check for empty response ---
    if [ -z "$api_response" ]; then
        log_error "API validation failed. Received an empty response from the server."
        log_fatal "The embedding model is not responding correctly."
    fi

    # --- Check if the response contains an error ---
    if echo "$api_response" | jq -e 'has("error")' > /dev/null; then
        log_error "API validation failed. The server returned an error."
        log_error "API Response:"
        echo "$api_response" | log_plain_output
        log_fatal "The embedding model appears to have failed to load correctly."
    fi

    # --- Check if the response contains a valid embedding data structure ---
    if ! echo "$api_response" | jq -e '.data[0].embedding | length > 0' > /dev/null; then
        log_error "API validation failed. The response format was unexpected or embedding is empty."
        log_error "API Response:"
        echo "$api_response" | log_plain_output
        log_fatal "The embedding model is not responding with valid embeddings."
    fi

    log_info "API validation successful! The embedding model is loaded and generating responses."
    log_info "Test query response snippet: $(echo "$api_response" | jq -r '.data[0].embedding[0:5]' | tr -d '\n')..."
}

# =====================================================================================
# Function: display_connection_info
# Description: Displays the final connection information for the user.
# =====================================================================================
display_connection_info() {
    local ip_address
    ip_address=$(jq_get_value "$CTID" ".network_config.ip" | cut -d'/' -f1)
    local model
    model=$(jq_get_value "$CTID" ".vllm_model")

    log_info "============================================================"
    log_info "Embedding API Server is now running and fully operational."
    log_info "============================================================"
    log_info "Connection Details:"
    log_info "  IP Address: $ip_address"
    log_info "  Port: 8000"
    log_info "  Model: $model"
    log_info ""
    log_info "Example curl command for embeddings:"
    log_info "  curl -X POST \"http://${ip_address}:8000/v1/embeddings\" \\"
    log_info "    -H \"Content-Type: application/json\" \\"
    log_info "    --data '{\"model\": \"$model\", \"input\": \"Your text to embed here.\"}'"
    log_info "============================================================"
}

# =====================================================================================
# Function: main
# Description: Main entry point for the application runner script.
# =====================================================================================
main() {
    parse_arguments "$@"
    generate_vllm_service_file
    manage_vllm_service
    if systemctl is-active --quiet "$VLLM_SERVICE_NAME"; then
        perform_health_check
        validate_api_with_test_query
    else
        log_info "Service $VLLM_SERVICE_NAME is not active. Skipping health check and API validation."
    fi
    display_connection_info
    exit_script 0
}

main "$@"