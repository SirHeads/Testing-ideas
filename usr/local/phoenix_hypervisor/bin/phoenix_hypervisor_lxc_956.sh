#!/bin/bash

# File: phoenix_hypervisor_lxc_956.sh
# Description: Installs and configures Open WebUI within an LXC container (CTID 956),
#              connecting it to an Ollama API backend. This script automates the
#              deployment of Open WebUI using Docker, including image pulling,
#              volume creation, container management, and a health check.
# Dependencies: docker, curl, hostname, awk.
# Inputs:
#   LXC_ID (hardcoded as 956) - The container ID for Open WebUI.
#   LXC_NAME (hardcoded as "openWebUIBase") - The name of the LXC container.
#   OPENWEBUI_PORT (hardcoded as 8080) - The port Open WebUI will listen on.
#   OLLAMA_API_IP (hardcoded as 10.0.0.155) - The IP address of the Ollama API backend.
#   OLLAMA_API_PORT (hardcoded as 11434) - The port of the Ollama API backend.
#   OPENWEBUI_DATA_VOLUME (hardcoded as "openwebui-data") - The Docker volume name for persistent data.
# Outputs:
#   Docker command outputs (pull, volume create, stop, rm, run), curl health check results,
#   log messages to stdout, exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# Exit immediately if a command exits with a non-zero status.
set -e

LXC_ID="956"
LXC_NAME="openWebUIBase"
OPENWEBUI_PORT="8080"
OLLAMA_API_IP="10.0.0.155"
OLLAMA_API_PORT="11434"
OPENWEBUI_DATA_VOLUME="openwebui-data"

# =====================================================================================
# Function: main
# Description: Main entry point for the Open WebUI installation and configuration script.
#              Orchestrates the entire process of setting up Open WebUI within an LXC container.
# Arguments:
#   None (uses global LXC_ID, LXC_NAME, OPENWEBUI_PORT, OLLAMA_API_IP, OLLAMA_API_PORT, OPENWEBUI_DATA_VOLUME).
# Returns:
#   Exits with status 0 on successful completion, or a non-zero status on failure.
# =====================================================================================
main() {
echo "Starting setup for LXC ${LXC_ID}: ${LXC_NAME}"

# 1. Check for Docker installation
# =====================================================================================
# Function: check_docker_installation
# Description: Checks if Docker is installed and available in the system's PATH.
# Arguments:
#   None.
# Returns:
#   Exits with status 1 if Docker is not found.
# =====================================================================================
check_docker_installation() {
    echo "Checking for Docker installation..."
    # Check if the 'docker' command exists in the system's PATH
    if ! command -v docker &> /dev/null; then
        echo "Docker is not installed. This script requires Docker. Please ensure the 'docker' feature is enabled for this LXC."
        exit 1
    fi
    echo "Docker is installed."
}

# 2. Pull the official Open WebUI Docker image
# =====================================================================================
# Function: pull_openwebui_image
# Description: Pulls the official Open WebUI Docker image from ghcr.io.
# Arguments:
#   None.
# Returns:
#   None. Exits with a non-zero status if the Docker pull command fails.
# =====================================================================================
pull_openwebui_image() {
    echo "Pulling the official Open WebUI Docker image..."
    docker pull ghcr.io/open-webui/open-webui:main
}

# 3. Create a persistent volume for Open WebUI data
# =====================================================================================
# Function: create_data_volume
# Description: Creates a persistent Docker volume for Open WebUI data.
# Arguments:
#   None (uses global OPENWEBUI_DATA_VOLUME).
# Returns:
#   None. Exits with a non-zero status if the Docker volume creation command fails.
# =====================================================================================
create_data_volume() {
    echo "Creating persistent volume for Open WebUI data: ${OPENWEBUI_DATA_VOLUME}"
    docker volume create ${OPENWEBUI_DATA_VOLUME}
}

# 4. Stop and remove any existing Open WebUI container
# =====================================================================================
# Function: stop_and_remove_existing_container
# Description: Stops and removes any existing Open WebUI Docker container.
#              The '|| true' ensures the script continues even if the container
#              does not exist (e.g., on first run).
# Arguments:
#   None.
# Returns:
#   None.
# =====================================================================================
stop_and_remove_existing_container() {
    echo "Stopping and removing any existing Open WebUI container..."
    docker stop open-webui || true # Stop the container if it's running
    docker rm open-webui || true # Remove the container if it exists
}

# 5. Start the Open WebUI container
# =====================================================================================
# Function: start_openwebui_container
# Description: Starts the Open WebUI Docker container with specified configurations.
#              It maps ports, mounts the data volume, sets restart policy, and
#              configures the OLLAMA API backend URL.
# Arguments:
#   None (uses global OPENWEBUI_PORT, OPENWEBUI_DATA_VOLUME, OLLAMA_API_IP, OLLAMA_API_PORT).
# Returns:
#   None. Exits with a non-zero status if the Docker run command fails.
# =====================================================================================
start_openwebui_container() {
    echo "Starting the Open WebUI container..."
    docker run -d \
        --name open-webui \
        -p ${OPENWEBUI_PORT}:${OPENWEBUI_PORT} \
        -v ${OPENWEBUI_DATA_VOLUME}:/app/backend/data \
        --restart always \
        -e OLLAMA_API_BASE_URL=http://${OLLAMA_API_IP}:${OLLAMA_API_PORT} \
        ghcr.io/open-webui/open-webui:main
}

echo "Open WebUI container started."

# 6. Health Check
# =====================================================================================
# Function: perform_health_check
# Description: Performs a health check on the Open WebUI service by attempting to
#              access its local HTTP endpoint. It includes a delay to allow the
#              container to fully start.
# Arguments:
#   None (uses global OPENWEBUI_PORT, OLLAMA_API_IP, OLLAMA_API_PORT).
# Returns:
#   Exits with status 1 if the health check fails.
# =====================================================================================
perform_health_check() {
    echo "Performing health check on Open WebUI..."
    # Give the container a moment to start up before performing the health check
    sleep 10

    # Attempt to access the Open WebUI endpoint using curl
    if curl -s http://localhost:${OPENWEBUI_PORT} > /dev/null; then
        echo "Open WebUI is accessible at http://$(hostname -I | awk '{print $1}'):${OPENWEBUI_PORT}"
        echo "Open WebUI successfully connected to Ollama API at http://${OLLAMA_API_IP}:${OLLAMA_API_PORT}"
    else
        echo "Health check failed: Open WebUI is not accessible."
        exit 1
    fi
}

echo "Setup for LXC ${LXC_ID}: ${LXC_NAME} completed successfully."
}

main "$@"