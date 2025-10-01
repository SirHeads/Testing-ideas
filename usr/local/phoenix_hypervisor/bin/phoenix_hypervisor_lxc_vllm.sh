#!/bin/bash
#
# File: phoenix_hypervisor_lxc_vllm.sh
# Description: This script is the application runner for vLLM containers. It is responsible for
#              dynamically generating a systemd service file based on the structured `vllm_engine_config`
#              object in `phoenix_lxc_configs.json`. It then deploys this service into the target
#              container and starts it, completing the vLLM setup.
#
# Version: 2.0.0
# Author: Phoenix Hypervisor Team
#
# Dependencies:
#   - `phoenix_hypervisor_common_utils.sh`: For logging and JSON parsing.
#   - `jq`: For advanced JSON manipulation.
#
# Inputs:
#   - $1 (CTID): The ID of the target LXC container.
#   - `phoenix_lxc_configs.json`: Reads the `.vllm_engine_config` object for the CTID.
#
# Outputs:
#   - A dynamically generated and deployed systemd service file inside the container.
#   - A running `vllm_model_server.service` inside the container.
#   - Logs detailing the entire process.
#   - Exits with 0 on success, non-zero on failure.

# --- Source common utilities ---
# Ensures reliable sourcing of shared functions regardless of script execution location.
source "$(dirname -- "${BASH_SOURCE[0]}")/phoenix_hypervisor_common_utils.sh"

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
# Function: parse_vllm_config
# Description: Parses the vllm_engine_config object from the JSON config file.
# Arguments:
#   $1 - The CTID of the container.
# Returns:
#   Exports the parsed configuration values as global variables.
# =====================================================================================
parse_vllm_config() {
    log_info "Parsing vLLM engine configuration for CTID $CTID..."
    export VLLM_CONFIG_JSON=$(jq_get_value "$CTID" ".vllm_engine_config")

    if [ -z "$VLLM_CONFIG_JSON" ] || [ "$VLLM_CONFIG_JSON" == "null" ]; then
        log_fatal "The '.vllm_engine_config' object was not found for CTID $CTID."
    fi
}

# =====================================================================================
# Function: build_vllm_cli_args
# Description: Constructs a string of command-line arguments from the parsed JSON config.
# Arguments: None (uses global VLLM_CONFIG_JSON).
# Returns:
#   A string containing all the formatted command-line arguments for vLLM.
# =====================================================================================
build_vllm_cli_args() {
    log_info "Building vLLM command-line arguments..."
    local args_string=""

    # Use jq to iterate through all key-value pairs in the config object
    while IFS="=" read -r key value; do
        # Convert camelCase to kebab-case (e.g., trustRemoteCode -> --trust-remote-code)
        local kebab_key=$(echo "$key" | sed -r 's/([A-Z])/-\L\1/g')
        
        # Handle boolean flags (e.g., "trust_remote_code": true)
        if [ "$value" == "true" ]; then
            args_string+=" --$kebab_key"
        # Handle key-value pairs (e.g., "model": "meta-llama/Llama-3.2-3B-Instruct")
        elif [ "$value" != "false" ] && [ "$value" != "null" ]; then
            args_string+=" --$kebab_key $value"
        fi
    done < <(echo "$VLLM_CONFIG_JSON" | jq -r '(.[] | to_entries[]) | "\(.key)=\(.value)"')

    echo "$args_string"
}

# =====================================================================================
# Function: generate_systemd_service_content
# Description: Dynamically generates the complete content for the systemd service file.
# Arguments:
#   $1 - The string of command-line arguments for the vLLM server.
# Returns:
#   The full content of the vllm_model_server.service file as a string.
# =====================================================================================
generate_systemd_service_content() {
    local vllm_args="$1"
    log_info "Generating systemd service file content..."

    # Using a HEREDOC for multiline content is cleaner and more maintainable.
    cat <<-EOF
[Unit]
Description=vLLM OpenAI-Compatible RESTful API Server
After=network.target

[Service]
User=root
WorkingDirectory=/opt/vllm
# Unset conflicting environment variables to ensure a clean environment
Environment="CUDA_HOME="
Environment="LD_LIBRARY_PATH="
# Set the correct environment for the vLLM service
Environment="CUDA_HOME=/usr/local/cuda"
Environment="LD_LIBRARY_PATH=/usr/local/cuda/lib64"
Environment="PATH=/opt/vllm/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="VLLM_USE_FLASHINFER_SAMPLER=1"
Environment="TORCH_CUDA_ARCH_LIST=12.0"
ExecStart=/opt/vllm/bin/python -m vllm.entrypoints.openai.api_server ${vllm_args}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

# =====================================================================================
# Function: deploy_and_start_service
# Description: Deploys the generated systemd service file to the container and starts it.
# Arguments:
#   $1 - The content of the systemd service file.
# Returns: None
# =====================================================================================
deploy_and_start_service() {
    local service_content="$1"
    local container_service_path="/etc/systemd/system/vllm_model_server.service"

    log_info "Deploying and starting vLLM service in CTID $CTID..."

    # 1. Write the generated content directly to the container's filesystem.
    #    This is executed from within the container, so we can write directly.
    log_info "Writing systemd service file directly to $container_service_path..."
    if ! echo "$service_content" > "$container_service_path"; then
        log_fatal "Failed to write systemd service file to $container_service_path."
    fi

    # 2. Reload systemd, enable, and start the service inside the container.
    log_info "Reloading systemd daemon and starting the service..."
    pct_exec "$CTID" -- systemctl daemon-reload
    pct_exec "$CTID" -- systemctl enable --now "$SERVICE_NAME"

    # 3. Verify the service started correctly.
    sleep 5 # Give the service a moment to start.
    if ! pct_exec "$CTID" -- systemctl is-active --quiet "$SERVICE_NAME"; then
        log_error "$SERVICE_NAME service failed to start. Retrieving recent logs..."
        pct_exec "$CTID" -- journalctl -u "$SERVICE_NAME" --no-pager -n 50 | log_plain_output
        log_fatal "Failed to start $SERVICE_NAME service in CTID $CTID."
    fi

    log_success "vLLM service is active and running in CTID $CTID."
}

# =====================================================================================
# Function: main
# Description: Main entry point that orchestrates the vLLM service deployment.
# =====================================================================================
main() {
    parse_arguments "$@"
    parse_vllm_config
    
    local vllm_args
    vllm_args=$(build_vllm_cli_args)
    
    local service_content
    service_content=$(generate_systemd_service_content "$vllm_args")
    
    deploy_and_start_service "$service_content"
    
    log_info "vLLM application script completed successfully for CTID $CTID."
    exit_script 0
}

main "$@"