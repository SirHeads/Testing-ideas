#!/bin/bash
#
# File: phoenix_hypervisor_lxc_vllm.sh
# Description: This script is a unified application runner for deploying and managing vLLM (Very Large Language Model)
#              API servers within an LXC container. It dynamically configures and manages a systemd service
#              based on parameters defined in the `phoenix_lxc_configs.json` file. The script handles the
#              entire lifecycle, including service configuration, startup, health checks, and API validation
#              for different model types (e.g., chat, embedding).
#
# Dependencies: - `phoenix_hypervisor_common_utils.sh` for logging and JSON parsing functions.
#               - `jq` command-line JSON processor.
#               - A pre-existing systemd service template file for the vLLM server.
#
# Inputs: - $1 (CTID): The ID of the LXC container where the vLLM server will be deployed.
#         - Configuration from `phoenix_lxc_configs.json` for the specified CTID, including:
#           - .vllm_model: The Hugging Face model identifier.
#           - .vllm_served_model_name: The name the model is served as.
#           - .vllm_model_type: The type of model ('chat' or 'embedding').
#           - .ports[]: The port mapping for the service.
#           - .vllm_args[]: An array of additional command-line arguments for the vLLM server.
#
# Outputs: - A dynamically configured and running systemd service named `vllm_model_server`.
#          - Log messages detailing the setup process.
#          - An exit code indicating success (0) or failure (non-zero).

# --- Source common utilities ---
# Ensures reliable sourcing of shared functions regardless of script execution location.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""
SERVICE_NAME="vllm_model_server"

# =====================================================================================
# Function: parse_arguments
# Description: Parses and validates the command-line arguments, expecting a single CTID.
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Executing vLLM application runner for CTID: $CTID"
}

# =====================================================================================
# Function: configure_systemd_service
# Description: Dynamically configures the vLLM systemd service file by replacing placeholder
#              values with configuration data read from `phoenix_lxc_configs.json`.
# =====================================================================================
configure_systemd_service() {
    log_info "Configuring vLLM systemd service in CTID: $CTID..."
    local service_file_path="/etc/systemd/system/vllm_model_server.service"

    # Retrieve vLLM configuration parameters using the jq_get_value helper.
    local model=$(jq_get_value "$CTID" ".vllm_model")
    local served_model_name=$(jq_get_value "$CTID" ".vllm_served_model_name")
    local port=$(jq_get_value "$CTID" ".ports[0]" | cut -d':' -f2)

    # Read the array of vLLM arguments and concatenate them into a single string.
    mapfile -t vllm_args < <(jq_get_array "$CTID" ".vllm_args[]")
    local args_string=""
    for arg in "${vllm_args[@]}"; do
        args_string+=" $arg"
    done

    # Use sed to perform in-place replacement of placeholders in the systemd template file.
    sed -i "s|VLLM_MODEL_PLACEHOLDER|$model|" "$service_file_path"
    sed -i "s|VLLM_SERVED_MODEL_NAME_PLACEHOLDER|$served_model_name|" "$service_file_path"
    sed -i "s|VLLM_PORT_PLACEHOLDER|$port|" "$service_file_path"
    sed -i "s|VLLM_ARGS_PLACEHOLDER|$args_string|" "$service_file_path"
}

# =====================================================================================
# Function: manage_vllm_service
# Description: Manages the systemd service for the vLLM server, including reloading the
#              daemon, enabling the service for auto-start, and restarting it.
# =====================================================================================
manage_vllm_service() {
    log_info "Managing the $SERVICE_NAME service in CTID $CTID..."
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    if ! systemctl restart "$SERVICE_NAME"; then
        log_error "$SERVICE_NAME service failed to start. Retrieving recent logs..."
        journalctl -u "$SERVICE_NAME" --no-pager -n 50 | log_plain_output
        log_fatal "Failed to start $SERVICE_NAME service."
    fi
    log_info "$SERVICE_NAME service started successfully."
}

# =====================================================================================
# Function: perform_health_check
# Description: Periodically checks the vLLM server's /health endpoint to ensure it has
#              started and is responsive before proceeding.
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
        # Use curl to check if the health endpoint returns a success status code.
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
# Description: Sends a model-specific test query to the vLLM API to confirm that the
#              model has loaded correctly and is producing valid outputs.
# =====================================================================================
validate_api_with_test_query() {
    log_info "Performing a final API validation with a test query..."
    local model_type=$(jq_get_value "$CTID" ".vllm_model_type")
    local model=$(jq_get_value "$CTID" ".vllm_served_model_name")
    local api_url=""
    local json_payload=""
    local curl_cmd=""
    local api_response=""

    # Dynamically construct the API endpoint and JSON payload based on the model type.
    if [ "$model_type" == "chat" ]; then
        api_url="http://localhost:8000/v1/chat/completions"
        json_payload=$(jq -c -n --arg model "$model" \
            '{"model": $model, "messages": [{"role": "user", "content": "What is the capital of France?"}]}')
    elif [ "$model_type" == "embedding" ]; then
        api_url="http://localhost:8000/v1/embeddings"
        json_payload=$(jq -c -n --arg model "$model" \
            '{"model": $model, "input": "This is a test sentence for embedding."}')
    else
        log_fatal "Invalid vllm_model_type specified in configuration: $model_type"
    fi

    # Execute the curl command to send the test query.
    curl_cmd="curl -s -X POST '$api_url' -H 'Content-Type: application/json' -d '$json_payload'"
    api_response=$(bash -c "$curl_cmd")

    if [ -z "$api_response" ]; then
        log_fatal "API validation failed. Received an empty response from the server."
    fi

    # Check if the JSON response contains an "error" key.
    if echo "$api_response" | jq -e 'has("error")' > /dev/null; then
        log_error "API validation failed. The server returned an error:"
        echo "$api_response" | log_plain_output
        log_fatal "The vLLM model failed to load or respond correctly."
    fi

    # Validate the structure of the response based on the model type.
    if [ "$model_type" == "chat" ]; then
        if ! echo "$api_response" | jq -e '.choices[0].message.content' > /dev/null; then
            log_fatal "API validation failed. The chat model response format was unexpected."
        fi
        log_info "Test query response snippet: $(echo "$api_response" | jq -r '.choices[0].message.content' | head -c 100)..."
    elif [ "$model_type" == "embedding" ]; then
        if ! echo "$api_response" | jq -e '.data[0].embedding | length > 0' > /dev/null; then
            log_fatal "API validation failed. The embedding model response format was unexpected."
        fi
        log_info "Test query response snippet: $(echo "$api_response" | jq -r '.data[0].embedding[0:5]' | tr -d '\n')..."
    fi

    log_info "API validation successful! The model is loaded and responding correctly."
}

# =====================================================================================
# Function: display_connection_info
# Description: Displays final connection information and example usage commands.
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
# Description: Main entry point that orchestrates the vLLM service deployment.
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