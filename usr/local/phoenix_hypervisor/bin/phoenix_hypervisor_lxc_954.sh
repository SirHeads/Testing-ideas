#!/bin/bash
#
# File: phoenix_hypervisor_lxc_954.sh
# Description: This script configures and launches the n8n workflow automation service within LXC container 954.
#              It serves as the final application-specific step in the orchestration process for this container.
#              The script uses Docker to run the n8n application, ensuring a consistent and isolated environment.
#              It also creates a persistent volume for n8n data, so workflows and credentials are not lost.
#
# Dependencies: - A running Docker service within the container.
#               - The main `phoenix_orchestrator.sh` script, which calls this script.
#
# Inputs: - CTID (Container ID): Implicitly 954.
#         - Port mappings and volume configurations are implicitly defined in this script but align with `phoenix_lxc_configs.json`.
#
# Outputs: - A running Docker container named "n8n" hosting the n8n workflow automation service.
#          - A persistent data volume for n8n located at `/home/node/.n8n` inside the container.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Logging Functions ---
# Basic logging functions to provide feedback during script execution.
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >&2
}

# --- Data Persistence ---
# Create a directory on the host to be used as a persistent volume for n8n data.
# This ensures that all workflows, credentials, and execution data are saved across container restarts.
log_info "Creating persistent data directory for n8n at /home/node/.n8n..."
mkdir -p /home/node/.n8n

# --- Docker Container Launch ---
# Run the official n8n Docker container.
# -d: Run the container in detached mode (in the background).
# --restart always: Ensure the container automatically restarts if it stops or on system reboot.
# --name n8n: Assign a predictable name to the container for easy management.
# -p 5678:5678: Map the container's port 5678 to the host's port 5678 to expose the n8n web interface.
# -v /home/node/.n8n:/home/node/.n8n: Mount the persistent data directory into the container.
log_info "Starting the n8n Docker container..."
docker run -d --restart always --name n8n -p 5678:5678 -v /home/node/.n8n:/home/node/.n8n n8nio/n8n

log_info "n8n container started successfully and is available at http://<container_ip>:5678."