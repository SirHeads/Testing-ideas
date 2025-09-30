#!/bin/bash
#
# File: phoenix_hypervisor_lxc_955.sh
# Description: This script configures and enables the Ollama service within LXC container 955.
#              It serves as the final application-specific step in the orchestration process for this container.
#              The script ensures the Ollama executable is in the system's PATH, creates a robust systemd service
#              for automatic startup and management, and then enables and starts the service. This provides a
#              standardized, GPU-accelerated base for running various Ollama models.
#
# Dependencies: - An installed Ollama binary (expected to be at /usr/bin/ollama).
#               - A systemd-based environment (e.g., Debian, Ubuntu).
#               - The `phoenix_hypervisor_common_utils.sh` script for logging.
#
# Inputs: - CTID (Container ID): The ID of the container, passed as the first argument ($1).
#
# Outputs: - A running and enabled `ollama.service` managed by systemd.
#          - The Ollama API will be listening on all network interfaces (0.0.0.0) on port 11434.

# --- Script Initialization ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Pipelines return the exit status of the last command to exit with a non-zero status.
set -o pipefail

# Determine the absolute directory of the script to reliably source other scripts.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
# Source shared utility functions for logging.
source "${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"

# --- Input Validation ---
# Check if the Container ID (CTID) was passed as an argument.
if [ "$#" -ne 1 ]; then
    log_error "Usage: $0 <CTID>"
    exit_script 2
fi
CTID="$1"

log_info "Starting Ollama application setup for CTID: $CTID"

# --- Environment Configuration ---
# Ensure the Ollama executable is accessible system-wide by adding its location to the PATH.
# This is done by creating a new script in /etc/profile.d/, which is the standard way to modify the PATH for all users.
log_info "Configuring system-wide PATH for Ollama..."
echo 'export PATH="$PATH:/usr/local/bin"' > /etc/profile.d/ollama.sh

# --- Systemd Service Management ---
# Create a systemd service unit file to manage the Ollama server process.
# This ensures that Ollama starts automatically on boot, restarts on failure, and is managed consistently.
log_info "Creating and enabling Ollama systemd service..."
cat <<EOF > /etc/systemd/system/ollama.service
[Unit]
Description=Ollama API Service
After=network-online.target

[Service]
# Command to start the Ollama server.
ExecStart=/usr/bin/ollama serve
User=root
Group=root
# Automatically restart the service if it fails.
Restart=always
RestartSec=3
# Set the host and port for the Ollama API. 0.0.0.0 makes it accessible from outside the container.
Environment="OLLAMA_HOST=0.0.0.0:11434"

[Install]
# Ensures the service is started at the multi-user system level.
WantedBy=multi-user.target
EOF

# Reload the systemd daemon to recognize the new service file.
systemctl daemon-reload
# Enable the service to start automatically at boot.
systemctl enable ollama.service
# Restart the service immediately to apply the configuration and start Ollama.
systemctl restart ollama.service

log_info "Ollama application setup complete for CTID $CTID."
exit_script 0