#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_ollama.sh
# Description: This modular feature script automates the installation and configuration of Ollama
#              within a specified LXC container. It handles the core installation, ensures the
#              Ollama binary is accessible via the system PATH, and sets up a robust systemd
#              service to manage the Ollama process automatically. This ensures that Ollama
#              starts on boot and is configured to listen on all network interfaces, making it
#              accessible for integration with other services like Open WebUI or direct API calls.
#              The script is idempotent and is invoked by the phoenix_orchestrator.sh when "ollama"
#              is listed in a container's `features` array in `phoenix_lxc_configs.json`.
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - `curl`: For downloading the Ollama installation script.
#   - `systemd`: For service management.
#   - NVIDIA feature: For GPU acceleration, the 'nvidia' feature should be installed first.
#
# Inputs:
#   - $1 (CTID): The unique Container ID for the target LXC container.
#
# Outputs:
#   - Installs the Ollama binary to /usr/local/bin inside the container.
#   - Creates a systemd service file at /etc/systemd/system/ollama.service.
#   - Enables and starts the Ollama service.
#   - Logs the entire process to stdout and the main log file.
#   - Returns exit code 0 on success, non-zero on failure.
#
# Version: 1.1.0
# Author: Phoenix Hypervisor Team

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""

# =====================================================================================
# Function: parse_arguments
# Description: Validates and parses the command-line arguments to get the CTID.
# Arguments:
#   $1 - The Container ID (CTID).
# Globals:
#   - CTID: Sets the global CTID variable.
# Returns:
#   - None. Exits with status 2 if the CTID is not provided.
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        log_error "This script requires the LXC Container ID to install the Ollama feature."
        exit_script 2
    fi
    CTID="$1"
    log_info "Executing Ollama modular feature for CTID: $CTID"
}

# =====================================================================================
# Function: install_ollama
# Description: Downloads and runs the official Ollama installation script.
# Arguments:
#   None. Relies on the global CTID.
# Returns:
#   - None. Exits on failure.
# =====================================================================================
install_ollama() {
    # Idempotency Check: If the ollama command is already available, skip the installation.
    if is_command_available "$CTID" "ollama"; then
        log_info "Ollama is already installed in CTID $CTID. Skipping installation."
        return 0
    fi

    log_info "Installing Ollama in CTID $CTID using the official install script..."
    # The official script handles the download and placement of the binary.
    if ! pct_exec "$CTID" -- bash -c "curl -fsSL https://ollama.com/install.sh | sh"; then
        log_fatal "Ollama installation script failed for CTID $CTID."
    fi
    log_success "Ollama binary successfully installed in CTID $CTID."
}

# =====================================================================================
# Function: configure_systemd_service
# Description: Creates and enables a systemd service for Ollama to ensure it runs
#              on boot and is managed properly. It also configures Ollama to listen
#              on all network interfaces.
# Arguments:
#   None. Relies on the global CTID.
# Returns:
#   - None. Exits on failure.
# =====================================================================================
configure_systemd_service() {
    log_info "Configuring systemd service for Ollama in CTID $CTID..."
    local service_file_path="/etc/systemd/system/ollama.service"

    # This heredoc creates the systemd service file inside the container.
    # OLLAMA_HOST=0.0.0.0:11434 is critical for making the API accessible from outside the container.
    pct_exec "$CTID" -- bash -c "cat <<EOF > ${service_file_path}
[Unit]
Description=Ollama API Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=root
Group=root
Restart=always
RestartSec=3
Environment=\"OLLAMA_HOST=0.0.0.0:11434\"

[Install]
WantedBy=multi-user.target
EOF"

    log_info "Reloading systemd daemon, enabling and starting the Ollama service..."
    pct_exec "$CTID" -- systemctl daemon-reload
    pct_exec "$CTID" -- systemctl enable ollama.service
    pct_exec "$CTID" -- systemctl restart ollama.service # Use restart to ensure it's running with the new config
    log_success "Ollama systemd service configured and started successfully."
}

# =====================================================================================
# Function: verify_installation
# Description: Verifies that the Ollama service is active and responding.
# Arguments:
#   None. Relies on the global CTID.
# Returns:
#   - None. Exits with a fatal error if verification fails.
# =====================================================================================
verify_installation() {
    log_info "Verifying Ollama installation in CTID: $CTID"
    # Check if the systemd service is active.
    if ! pct_exec "$CTID" -- systemctl is-active --quiet ollama.service; then
        log_fatal "Ollama service is not active in CTID $CTID. Check logs with 'journalctl -u ollama.service'."
    fi

    # Perform a direct API call to ensure the service is responding.
    if ! pct_exec "$CTID" -- curl --fail http://127.0.0.1:11434/api/tags > /dev/null; then
        log_fatal "Failed to get a successful response from the Ollama API at http://127.0.0.1:11434."
    fi

    log_success "Ollama installation verified successfully. The service is active and responding."
}


# =====================================================================================
# Function: main
# Description: Main entry point for the Ollama feature script.
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   - Exits with status 0 on successful completion.
# =====================================================================================
main() {
    parse_arguments "$@"
    install_ollama
    configure_systemd_service
    verify_installation
    log_info "Successfully completed Ollama feature for CTID $CTID."
    exit_script 0
}

# Execute the main function, passing all script arguments to it.
main "$@"