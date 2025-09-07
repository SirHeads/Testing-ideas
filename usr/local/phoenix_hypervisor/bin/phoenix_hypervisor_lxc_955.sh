#!/bin/bash
#
# File: phoenix_hypervisor_lxc_955.sh
# Description: Manages the deployment and lifecycle of an Ollama base container (CTID 955).
#              This script handles the installation of the Ollama service, its systemd
#              service management (enable/start), and performs health checks to ensure
#              Ollama is running and GPU resources are properly detected.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), curl, sh (for install script),
#               systemctl, journalctl, nvidia-smi (for GPU detection).
# Inputs:
#   $1 (CTID) - The container ID for the Ollama base container.
# Outputs:
#   Ollama installation logs, systemd service management output, HTTP response codes
#   from health checks, nvidia-smi output (for GPU check), log messages to stdout
#   and MAIN_LOG_FILE, exit codes indicating success or failure.
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
SERVICE_NAME="ollama"
OLLAMA_API_PORT="11434"

# =====================================================================================
# Function: parse_arguments
# Description: Parses the CTID from command-line arguments.
# =====================================================================================
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
# Function: install_ollama
# Description: Installs the Ollama service inside the specified LXC container.
#              It uses the official Ollama installation script, which is designed
#              to be idempotent and handles its own dependencies and service setup.
# Arguments:
#   None (uses global CTID).
# Returns:
#   Exits with a fatal error if the Ollama installation script fails.
# =====================================================================================
install_ollama() {
    log_info "Installing Ollama in CTID: $CTID..."
    # Execute the official Ollama installation script inside the container.
    # The script handles dependencies and service setup and is idempotent.
    if ! pct_exec "$CTID" bash -c "curl -fsSL https://ollama.com/install.sh | sh"; then
        log_fatal "Failed to install Ollama in CTID $CTID."
    fi
    log_info "Ollama installation complete."
}

# =====================================================================================
# Function: manage_ollama_service
# Description: Manages the Ollama systemd service within the specified LXC container.
#              This includes reloading the systemd daemon, enabling the service to start
#              on boot, and starting/restarting the service. It also provides error
#              logging and retrieves journalctl logs on service startup failure.
# Arguments:
#   None (uses global CTID and SERVICE_NAME).
# Returns:
#   Exits with a fatal error if systemd daemon reload, service enable, or service start fails.
# =====================================================================================
manage_ollama_service() {
    log_info "Managing the $SERVICE_NAME service in CTID $CTID..."

    # --- Reload the systemd daemon to recognize the new service ---
    # Reload the systemd daemon to recognize any changes to service files
    log_info "Reloading systemd daemon..."
    if ! pct_exec "$CTID" systemctl daemon-reload; then
        log_fatal "Failed to reload systemd daemon in CTID $CTID."
    fi

    # --- Enable the service to start on boot ---
    # Enable the Ollama service to ensure it starts automatically on container boot
    log_info "Enabling $SERVICE_NAME service..."
    if ! pct_exec "$CTID" systemctl enable "$SERVICE_NAME"; then
        log_fatal "Failed to enable $SERVICE_NAME service in CTID $CTID."
    fi

    # --- Start the service ---
    # Start (or restart if already running) the Ollama service
    log_info "Starting $SERVICE_NAME service..."
    if ! pct_exec "$CTID" systemctl restart "$SERVICE_NAME"; then
        log_error "$SERVICE_NAME service failed to start. Retrieving logs..."
        local journal_logs
        # If the service fails to start, retrieve and log the latest journalctl logs for diagnosis
        journal_logs=$(pct_exec "$CTID" journalctl -u "$SERVICE_NAME" --no-pager -n 50)
        log_error "Recent logs for $SERVICE_NAME:"
        log_plain_output "$journal_logs" # Log the retrieved journal entries
        log_fatal "Failed to start $SERVICE_NAME service. See logs above for details."
    fi

    log_info "$SERVICE_NAME service started successfully."
}

# =====================================================================================
# Function: perform_health_check
# Description: Performs a health check on the Ollama service within the specified
#              LXC container to ensure it is running and that GPU resources are
#              properly detected by `nvidia-smi`. It retries multiple times with a delay.
# Arguments:
#   None (uses global CTID, SERVICE_NAME, OLLAMA_API_PORT).
# Returns:
#   0 on successful health check (Ollama API responsive and GPU detected), exits with
#   a fatal error if the health check fails after all attempts.
# =====================================================================================
perform_health_check() {
    log_info "Performing health check on the Ollama service and GPU..."
    local max_attempts=12 # Maximum number of health check attempts
    local attempt=0 # Current attempt counter
    local interval=10 # Delay between attempts in seconds
    local ollama_url="http://localhost:${OLLAMA_API_PORT}" # Ollama API endpoint

    # Loop to perform health checks until successful or max attempts reached
    while [ "$attempt" -lt "$max_attempts" ]; do
        attempt=$((attempt + 1)) # Increment attempt counter
        log_info "Health check attempt $attempt/$max_attempts..."
        
        local response_code
        # Execute curl command inside the container to check the Ollama API,
        # capturing only the HTTP response code.
        response_code=$(pct exec "$CTID" -- curl -s -o /dev/null -w "%{http_code}" "$ollama_url" || echo "CURL_ERROR")

        # Check the response code from the curl command
        if [ "$response_code" == "CURL_ERROR" ]; then
            log_info "Ollama API not ready yet (curl command failed, likely connection refused). Retrying in $interval seconds..."
            sleep "$interval" # Wait before retrying
            continue # Continue to the next attempt
        elif [ "$response_code" == "200" ]; then
            log_info "Ollama API is responsive. Verifying GPU detection..."
            # Check if nvidia-smi runs successfully inside the container to confirm GPU detection
            if pct_exec "$CTID" nvidia-smi > /dev/null 2>&1; then
                log_info "GPU detected by nvidia-smi. Ollama health check passed!"
                return 0 # Health check successful
            else
                log_warn "nvidia-smi command failed in CTID $CTID. GPU might not be properly configured. Retrying in $interval seconds..."
                sleep "$interval" # Wait before retrying
            fi
        else
            log_info "Ollama API returned HTTP status code: $response_code. Retrying in $interval seconds..."
            sleep "$interval" # Wait before retrying
        fi
    done

    log_error "Health check failed after $max_attempts attempts. Ollama is not responsive or GPU is not detected."
    log_error "Retrieving latest service logs for diagnosis..."
    log_error "Recent logs for $SERVICE_NAME:"
    pct_exec "$CTID" journalctl -u "$SERVICE_NAME" --no-pager -n 50 | log_plain_output
    log_fatal "Ollama service health check failed."
}

# =====================================================================================
# Function: display_connection_info
# Description: Displays the final connection details for the Ollama base container,
#              including its IP address and the Ollama API port, along with an
#              example curl command for interaction.
# Arguments:
#   None (uses global CTID and OLLAMA_API_PORT).
# Returns:
#   None.
# =====================================================================================
display_connection_info() {
    local ip_address
    ip_address=$(jq_get_value "$CTID" ".network_config.ip" | cut -d'/' -f1) # Extract IP address from network config

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
# Description: Main entry point for the Ollama base container application runner script.
#              Orchestrates the entire process of installing, managing, and verifying
#              the Ollama service within an LXC container.
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   Exits with status 0 on successful completion, or a non-zero status on failure
#   (handled by exit_script).
# =====================================================================================
main() {
    parse_arguments "$@" # Parse command-line arguments
    install_ollama # Install Ollama
    manage_ollama_service # Enable and start the Ollama service
    perform_health_check # Perform a health check on Ollama and GPU detection
    display_connection_info # Display connection information to the user
    exit_script 0 # Exit successfully
}

main "$@"