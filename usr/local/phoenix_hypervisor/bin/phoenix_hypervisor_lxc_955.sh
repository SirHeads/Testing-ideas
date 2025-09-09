#!/bin/bash
#
# File: phoenix_hypervisor_lxc_955.sh
# Description: Manages the deployment and lifecycle of an Ollama base container (CTID 955).
#              This script handles the installation of the Ollama service, its systemd
#              service management (enable/start), and performs health checks to ensure
#              Ollama is running and GPU resources are properly detected.
# Dependencies: curl, sh (for install script),
#               systemctl, journalctl, nvidia-smi (for GPU detection).
# Inputs:
#   $1 (CTID) - The container ID for the Ollama base container.
# Outputs:
#   Ollama installation logs, systemd service management output, HTTP response codes
#   from health checks, nvidia-smi output (for GPU check), log messages to stdout
#   and MAIN_LOG_FILE, exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Embedded Common Utilities ---

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Global Constants ---
export LXC_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
export MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"

# --- Color Codes ---
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# --- Logging Functions ---
log_info() {
    echo -e "${COLOR_GREEN}$(date '+%Y-%m-%d %H:%M:%S') [INFO] $(basename "$0"): $*${COLOR_RESET}" | tee -a "$MAIN_LOG_FILE"
}

log_warn() {
	echo -e "${COLOR_YELLOW}$(date '+%Y-%m-%d %H:%M:%S') [WARN] $(basename "$0"): $*${COLOR_RESET}" | tee -a "$MAIN_LOG_FILE" >&2
}

log_error() {
    echo -e "${COLOR_RED}$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $(basename "$0"): $*${COLOR_RESET}" | tee -a "$MAIN_LOG_FILE" >&2
}

log_fatal() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [FATAL] $(basename "$0"): $*" | tee -a "$MAIN_LOG_FILE" >&2
    exit 1
}

log_plain_output() {
    while IFS= read -r line; do
        echo "    | $line" | tee -a "$MAIN_LOG_FILE"
    done
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

pct_exec() {
    # This function is a placeholder when run inside the container.
    # It executes commands directly.
    local ctid="$1"
    shift
    log_info "Executing in CTID $ctid: $*"
    if ! "$@"; then
        log_error "Command failed in CTID $ctid: '$*'"
        return 1
    fi
    return 0
}

jq_get_value() {
    local ctid="$1"
    local jq_query="$2"
    local value
    value=$(jq -r --arg ctid "$ctid" ".lxc_configs[\$ctid | tostring] | ${jq_query}" "$LXC_CONFIG_FILE")
    if [ "$?" -ne 0 ]; then
        log_error "jq command failed for CTID $ctid with query '${jq_query}'."
        return 1
    elif [ -z "$value" ] || [ "$value" == "null" ]; then
        return 1
    fi
    echo "$value"
    return 0
}

# --- End of Embedded Utilities ---

# --- Script Variables ---
CTID=""
SERVICE_NAME="ollama"
OLLAMA_API_PORT="11434"

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
# Function: install_ollama
# Description: Installs the Ollama service inside the specified LXC container.
# =====================================================================================
install_ollama() {
    log_info "Installing Ollama in CTID: $CTID..."
    if ! bash -c "curl -fsSL https://ollama.com/install.sh | sh"; then
        log_fatal "Failed to install Ollama in CTID $CTID."
    fi
    log_info "Ollama installation complete."
}

# =====================================================================================
# Function: manage_ollama_service
# Description: Manages the Ollama systemd service within the specified LXC container.
# =====================================================================================
manage_ollama_service() {
    log_info "Managing the $SERVICE_NAME service in CTID $CTID..."
    log_info "Setting OLLAMA_HOST environment variable..."
    if ! systemctl set-environment OLLAMA_HOST=0.0.0.0; then
        log_fatal "Failed to set OLLAMA_HOST environment variable in CTID $CTID."
    fi
    log_info "Reloading systemd daemon..."
    if ! systemctl daemon-reload; then
        log_fatal "Failed to reload systemd daemon in CTID $CTID."
    fi
    log_info "Enabling $SERVICE_NAME service..."
    if ! systemctl enable "$SERVICE_NAME"; then
        log_fatal "Failed to enable $SERVICE_NAME service in CTID $CTID."
    fi
    log_info "Starting $SERVICE_NAME service..."
    if ! systemctl restart "$SERVICE_NAME"; then
        log_error "$SERVICE_NAME service failed to start. Retrieving logs..."
        local journal_logs
        journal_logs=$(journalctl -u "$SERVICE_NAME" --no-pager -n 50)
        log_error "Recent logs for $SERVICE_NAME:"
        log_plain_output "$journal_logs"
        log_fatal "Failed to start $SERVICE_NAME service. See logs above for details."
    fi
    log_info "$SERVICE_NAME service started successfully."
}

# =====================================================================================
# Function: perform_health_check
# Description: Performs a health check on the Ollama service.
# =====================================================================================
perform_health_check() {
    log_info "Performing health check on the Ollama service and GPU..."
    local max_attempts=12
    local attempt=0
    local interval=10
    local ollama_url="http://localhost:${OLLAMA_API_PORT}"

    while [ "$attempt" -lt "$max_attempts" ]; do
        attempt=$((attempt + 1))
        log_info "Health check attempt $attempt/$max_attempts..."
        
        local response_code
        response_code=$(curl -s -o /dev/null -w "%{http_code}" "$ollama_url" || echo "CURL_ERROR")

        if [ "$response_code" == "CURL_ERROR" ]; then
            log_info "Ollama API not ready yet (curl command failed, likely connection refused). Retrying in $interval seconds..."
            sleep "$interval"
            continue
        elif [ "$response_code" == "200" ]; then
            log_info "Ollama API is responsive. Verifying GPU detection..."
            if nvidia-smi > /dev/null 2>&1; then
                log_info "GPU detected by nvidia-smi. Ollama health check passed!"
                return 0
            else
                log_warn "nvidia-smi command failed in CTID $CTID. GPU might not be properly configured. Retrying in $interval seconds..."
                sleep "$interval"
            fi
        else
            log_info "Ollama API returned HTTP status code: $response_code. Retrying in $interval seconds..."
            sleep "$interval"
        fi
    done

    log_error "Health check failed after $max_attempts attempts. Ollama is not responsive or GPU is not detected."
    log_error "Retrieving latest service logs for diagnosis..."
    log_error "Recent logs for $SERVICE_NAME:"
    journalctl -u "$SERVICE_NAME" --no-pager -n 50 | log_plain_output
    log_fatal "Ollama service health check failed."
}

# =====================================================================================
# Function: display_connection_info
# Description: Displays the final connection details for the Ollama base container.
# =====================================================================================
display_connection_info() {
    local ip_address
    ip_address=$(hostname -I | awk '{print $1}')

    log_info "============================================================"
    log_info "Ollama Base Container is now running and fully operational."
    log_info "============================================================"
    log_info "Connection Details:"
    log_info "  IP Address: $ip_address"
    log_info "  Ollama API Port: $OLLAMA_API_PORT"
    log_info ""
    log_info "To interact with Ollama, you can use the following command from your host:"
    log_info "  curl -X POST http://${ip_address}:${OLLAMA_API_PORT}/api/generate -d '{ \"model\": \"llama2\", \"prompt\": \"Why is the sky blue?\" }'"
    log_info "============================================================"
}

# =====================================================================================
# Function: main
# Description: Main entry point for the script.
# =====================================================================================
main() {
    # Since this script runs inside the container, CTID is not passed.
    # We'll assign a placeholder value.
    parse_arguments "955"
    install_ollama
    manage_ollama_service
    perform_health_check
    display_connection_info
    exit_script 0
}

main "$@"