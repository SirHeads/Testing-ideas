#!/bin/bash
#
# File: phoenix_hypervisor_lxc_951.sh
# Description: Manages the deployment and lifecycle of a vLLM API server within an LXC container (CTID 951).
#              This script handles environment verification, dynamic systemd service file generation,
#              service management (enable/start), and health checks to ensure the vLLM server
#              is running correctly and serving the specified model for embeddings.
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
source "$(dirname "$0")/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""
SERVICE_NAME="vllm_api_server"

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
# Function: verify_vllm_environment
# Description: Checks that the vLLM executable is present and has the correct permissions.
# =====================================================================================
verify_vllm_environment() {
    log_info "Verifying vLLM environment in CTID: $CTID..."
    local python_executable="/opt/vllm/bin/python3"

    if ! pct_exec "$CTID" test -f "$python_executable"; then
        log_error "vLLM python executable not found at $python_executable."
        log_error "Listing contents of /opt/vllm/bin/:"
        pct_exec "$CTID" ls -l /opt/vllm/bin/ | log_plain_output
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
# Description: Dynamically creates a systemd service file for the vLLM server.
# =====================================================================================
generate_systemd_service_file() {
    log_info "Generating systemd service file for $SERVICE_NAME..."

    # --- Retrieve vLLM parameters from the central config ---
    local model
    model=$(jq_get_value "$CTID" ".vllm_model")
    local tensor_parallel_size
    tensor_parallel_size=$(jq_get_value "$CTID" ".vllm_tensor_parallel_size")
    local gpu_memory_utilization
    gpu_memory_utilization=$(jq_get_value "$CTID" ".vllm_gpu_memory_utilization")
    local max_model_len
    max_model_len=$(jq_get_value "$CTID" ".vllm_max_model_len")

    # --- Construct the ExecStart command ---
    local exec_start_cmd="/opt/vllm/bin/python3 -m vllm.entrypoints.api_server"
    exec_start_cmd+=" --model $model"
    exec_start_cmd+=" --tensor-parallel-size $tensor_parallel_size"
    exec_start_cmd+=" --gpu-memory-utilization $gpu_memory_utilization"
    exec_start_cmd+=" --max-model-len $max_model_len"
    exec_start_cmd+=" --kv-cache-dtype auto"
    exec_start_cmd+=" --disable-custom-all-reduce"
    exec_start_cmd+=" --host 0.0.0.0"

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
    local service_file_path="/etc/systemd/system/${SERVICE_NAME}.service"
    log_info "Writing systemd service file to $service_file_path in CTID $CTID..."

    # --- Use a here-doc and pipe it into the container for maximum reliability ---
    if ! echo "${service_file_content}" | pct exec "$CTID" -- tee "${service_file_path}" > /dev/null; then
        log_fatal "Failed to write systemd service file in CTID $CTID."
    fi

    log_info "Systemd service file generated successfully."
}

# =====================================================================================
# Function: manage_vllm_service
# Description: Enables and starts the vLLM systemd service.
# =====================================================================================
manage_vllm_service() {
    log_info "Managing the $SERVICE_NAME service in CTID $CTID..."

    # --- Reload the systemd daemon to recognize the new service ---
    log_info "Reloading systemd daemon..."
    if ! pct_exec "$CTID" systemctl daemon-reload; then
        log_fatal "Failed to reload systemd daemon in CTID $CTID."
    fi

    # --- Enable the service to start on boot ---
    log_info "Enabling $SERVICE_NAME service..."
    if ! pct_exec "$CTID" systemctl enable "$SERVICE_NAME"; then
        log_fatal "Failed to enable $SERVICE_NAME service in CTID $CTID."
    fi

    # --- Start the service ---
    log_info "Starting $SERVICE_NAME service..."
    if ! pct_exec "$CTID" systemctl restart "$SERVICE_NAME"; then
        log_error "$SERVICE_NAME service failed to start. Retrieving logs..."
        # --- If the service fails, grab the latest logs from journalctl ---
        local journal_logs
        journal_logs=$(pct_exec "$CTID" journalctl -u "$SERVICE_NAME" --no-pager -n 50)
        log_error "Recent logs for $SERVICE_NAME:"
        log_plain_output "$journal_logs"
        log_fatal "Failed to start $SERVICE_NAME service. See logs above for details."
    fi

    log_info "$SERVICE_NAME service started successfully."
}

# =====================================================================================
# Function: perform_health_check
# Description: Performs a health check to ensure the vLLM API is responsive.
# =====================================================================================
perform_health_check() {
    log_info "Performing health check on the vLLM API server..."
    local max_attempts=12
    local attempt=0
    local interval=10 # seconds
    local health_check_url="http://localhost:8000/v1/models"
    local model_name
    model_name=$(jq_get_value "$CTID" ".vllm_model")

    while [ "$attempt" -lt "$max_attempts" ]; do
        attempt=$((attempt + 1))
        log_info "Health check attempt $attempt/$max_attempts..."
        
        local response
        response=$(pct exec "$CTID" -- curl -s "$health_check_url" || echo "CURL_ERROR")

        if [ "$response" == "CURL_ERROR" ]; then
            log_info "API not ready yet (curl command failed, likely connection refused). Retrying in $interval seconds..."
            sleep "$interval"
            continue
        fi

        local model_id
        model_id=$(echo "$response" | jq -r ".data.id")

        if [ "$model_id" == "$model_name" ]; then
            log_info "Health check passed! The vLLM API server is responsive and the correct model is loaded."
            return 0
        else
            log_info "API is responsive, but the model is not yet loaded. Retrying in $interval seconds..."
            sleep "$interval"
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
# Description: Sends a test query to the API to confirm the model is loaded and working for embeddings.
# =====================================================================================
validate_api_with_test_query() {
    log_info "Performing a final API validation with a test query for embeddings..."
    local model
    model=$(jq_get_value "$CTID" ".vllm_model")
    local api_url="http://localhost:8000/v1/embeddings"
    
    # --- Construct the JSON payload for the test query ---
    local json_payload
    json_payload=$(jq -n --arg model "$model" \
        '{model: $model, input: "This is a test sentence for embedding."}')

    # --- Execute the curl command inside the container ---
    local api_response
    api_response=$(pct_exec "$CTID" curl -s -X POST "$api_url" \
        -H "Content-Type: application/json" \
        -d "$json_payload")

    # --- Check if the response contains an error ---
    if echo "$api_response" | jq -e 'has("error")' > /dev/null; then
        log_error "API validation failed. The server returned an error."
        log_error "API Response:"
        echo "$api_response" | log_plain_output
        log_fatal "The vLLM embedding model appears to have failed to load correctly."
    fi

    # --- Check if the response contains a valid embedding data structure ---
    if ! echo "$api_response" | jq -e '.data.embedding | length > 0' > /dev/null; then
        log_error "API validation failed. The response format was unexpected or embedding is empty."
        log_error "API Response:"
        echo "$api_response" | log_plain_output
        log_fatal "The vLLM embedding model is not responding with valid embeddings."
    fi

    log_info "API validation successful! The embedding model is loaded and generating responses."
    log_info "Test query response snippet: $(echo "$api_response" | jq -r '.data.embedding[0:5]' | tr -d '\n')..."
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
    log_info "vLLM API Server is now running and fully operational."
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
    verify_vllm_environment
    generate_systemd_service_file
    manage_vllm_service
    perform_health_check
    validate_api_with_test_query
    display_connection_info
    exit_script 0
}

main "$@"