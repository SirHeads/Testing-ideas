#!/bin/bash
#
# File: phoenix_hypervisor_lxc_vllm.sh
# Description: Manages the deployment and lifecycle of a vLLM API server within an LXC container.
#              This script handles environment verification, dynamic systemd service file generation,
#              service management, and health checks to ensure the vLLM server is running correctly.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq.
# Inputs:
#   $1 (CTID) - The container ID for the vLLM server.
#   Configuration values from LXC_CONFIG_FILE: .vllm_model, .vllm_model_type, etc.
# Outputs:
#   Systemd service file for vLLM API server, log messages, API responses, exit codes.
# Version: 1.0.0
# Author: Roo

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""
SERVICE_NAME="vllm_model_server"

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
# Function: configure_systemd_service
# Description: Configures the vLLM systemd service by replacing placeholders.
# =====================================================================================
configure_systemd_service() {
    log_info "Configuring vLLM systemd service in CTID: $CTID..."
    local service_file_path="/etc/systemd/system/vllm_model_server.service"

    local model=$(jq_get_value "$CTID" ".vllm_model")
    local served_model_name=$(jq_get_value "$CTID" ".vllm_served_model_name")
    local port=$(jq_get_value "$CTID" ".ports[0]" | cut -d':' -f2)

    mapfile -t vllm_args < <(jq_get_array "$CTID" ".vllm_args[]")
    local args_string=""
    for arg in "${vllm_args[@]}"; do
        args_string+=" $arg"
    done

    sed -i "s|VLLM_MODEL_PLACEHOLDER|$model|" "$service_file_path"
    sed -i "s|VLLM_SERVED_MODEL_NAME_PLACEHOLDER|$served_model_name|" "$service_file_path"
    sed -i "s|VLLM_PORT_PLACEHOLDER|$port|" "$service_file_path"
    sed -i "s|VLLM_ARGS_PLACEHOLDER|$args_string|" "$service_file_path"
}

# =====================================================================================
# Function: manage_vllm_service
# Description: Enables and starts the vLLM model server systemd service.
# =====================================================================================
manage_vllm_service() {
    log_info "Managing the $SERVICE_NAME service in CTID $CTID..."
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    if ! systemctl restart "$SERVICE_NAME"; then
        log_error "$SERVICE_NAME service failed to start. Retrieving logs..."
        journalctl -u "$SERVICE_NAME" --no-pager -n 50 | log_plain_output
        log_fatal "Failed to start $SERVICE_NAME service."
    fi
    log_info "$SERVICE_NAME service started successfully."
}

# =====================================================================================
# Function: perform_health_check
# Description: Performs a health check to ensure the vLLM API is responsive.
# =====================================================================================
perform_health_check() {
    log_info "Performing health check on the vLLM API server..."
    local max_attempts=20
    local attempt=0
    local interval=10
    local health_check_url="http://localhost:8000/health"

    while [ "$attempt" -lt "$max_attempts" ]; do
        attempt=$((attempt + 1))
        log_info "Health check attempt $attempt/$max_attempts..."
        if curl -s --fail "$health_check_url" > /dev/null; then
            log_info "Health check passed! The vLLM API server is responsive."
            return 0
        else
            log_info "API not ready yet. Retrying in $interval seconds..."
            sleep "$interval"
        fi
    done

    log_error "Health check failed after $max_attempts attempts."
    journalctl -u "$SERVICE_NAME" --no-pager -n 50 | log_plain_output
    log_fatal "vLLM service health check failed."
}

# =====================================================================================
# Function: validate_api_with_test_query
# Description: Sends a test query to the API to confirm the model is loaded and working.
# =====================================================================================
validate_api_with_test_query() {
    log_info "Performing a final API validation with a test query..."
    local model_type=$(jq_get_value "$CTID" ".vllm_model_type")
    local model=$(jq_get_value "$CTID" ".vllm_served_model_name")
    local api_url=""
    local json_payload=""
    local curl_cmd=""
    local api_response=""

    if [ "$model_type" == "chat" ]; then
        api_url="http://localhost:8000/v1/chat/completions"
        json_payload=$(jq -c -n --arg model "$model" \
            '{"model": $model, "messages": [{"role": "user", "content": "What is the capital of France?"}]}')
    elif [ "$model_type" == "embedding" ]; then
        api_url="http://localhost:8000/v1/embeddings"
        json_payload=$(jq -c -n --arg model "$model" \
            '{"model": $model, "input": "This is a test sentence for embedding."}')
    else
        log_fatal "Invalid vllm_model_type: $model_type"
    fi

    curl_cmd="curl -s -X POST '$api_url' -H 'Content-Type: application/json' -d '$json_payload'"
    api_response=$(bash -c "$curl_cmd")

    if [ -z "$api_response" ]; then
        log_fatal "API validation failed. Received an empty response."
    fi

    if echo "$api_response" | jq -e 'has("error")' > /dev/null; then
        log_error "API validation failed. The server returned an error."
        echo "$api_response" | log_plain_output
        log_fatal "The vLLM model failed to load correctly."
    fi

    if [ "$model_type" == "chat" ]; then
        if ! echo "$api_response" | jq -e '.choices[0].message.content' > /dev/null; then
            log_fatal "API validation failed. Unexpected response format for chat model."
        fi
        log_info "Test query response snippet: $(echo "$api_response" | jq -r '.choices[0].message.content' | head -c 100)..."
    elif [ "$model_type" == "embedding" ]; then
        if ! echo "$api_response" | jq -e '.data[0].embedding | length > 0' > /dev/null; then
            log_fatal "API validation failed. Unexpected response format for embedding model."
        fi
        log_info "Test query response snippet: $(echo "$api_response" | jq -r '.data[0].embedding[0:5]' | tr -d '\n')..."
    fi

    log_info "API validation successful!"
}

# =====================================================================================
# Function: display_connection_info
# Description: Displays the final connection information for the user.
# =====================================================================================
display_connection_info() {
    local ip_address=$(jq_get_value "$CTID" ".network_config.ip" | cut -d'/' -f1)
    local model=$(jq_get_value "$CTID" ".vllm_model")
    local model_type=$(jq_get_value "$CTID" ".vllm_model_type")

    log_info "============================================================"
    log_info "vLLM API Server is now running and fully operational."
    log_info "============================================================"
    log_info "Connection Details:"
    log_info "  IP Address: $ip_address"
    log_info "  Port: 8000"
    log_info "  Model: $model"
    log_info "  Model Type: $model_type"
    log_info ""
    log_info "Example curl command:"
    if [ "$model_type" == "chat" ]; then
        log_info "  curl -X POST \"http://${ip_address}:8000/v1/chat/completions\" \\"
        log_info "    -H \"Content-Type: application/json\" \\"
        log_info "    --data '{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Write a python function to download a file.\"}]}'"
    elif [ "$model_type" == "embedding" ]; then
        log_info "  curl -X POST \"http://${ip_address}:8000/v1/embeddings\" \\"
        log_info "    -H \"Content-Type: application/json\" \\"
        log_info "    --data '{\"model\": \"$model\", \"input\": \"Your text to embed here.\"}'"
    fi
    log_info "============================================================"
}

# =====================================================================================
# Function: main
# Description: Main entry point for the application runner script.
# =====================================================================================
main() {
    parse_arguments "$@"
    configure_systemd_service
    manage_vllm_service
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        perform_health_check
        validate_api_with_test_query
    else
        log_info "Service $SERVICE_NAME is not active. Skipping health check and API validation."
    fi
    display_connection_info
    exit_script 0
}

main "$@"