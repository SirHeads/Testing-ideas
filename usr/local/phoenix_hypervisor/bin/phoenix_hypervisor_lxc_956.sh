#!/bin/bash

# File: phoenix_hypervisor_lxc_956.sh
# Description: This script configures and launches the Open WebUI service within LXC container 956.
#              It serves as the final application-specific step in the orchestration process for this container.
#              The script automates the deployment of Open WebUI using Docker, which provides a web-based
#              user interface for interacting with the backend Ollama API service. The script handles
#              Docker checks, image pulling, persistent volume creation, and container lifecycle management.
#
# Dependencies: - A running Docker service within the container.
#               - The Ollama service running in container 955 (at 10.0.0.155:11434).
#               - `curl` for health checks.
#
# Inputs: - CTID (Container ID): Implicitly 956.
#         - Configuration values are hardcoded but align with the central `phoenix_lxc_configs.json`.
#
# Outputs: - A running Docker container named "open-webui" hosting the Open WebUI service.
#          - A persistent Docker volume named "openwebui-data" for application data.
#          - The service is accessible at http://<container_ip>:8080.

# --- Script Initialization ---
# Exit immediately if a command exits with a non-zero status to prevent unintended behavior.
set -e

# --- Configuration Variables ---
# Hardcoded configuration values for the Open WebUI container.
# These should align with the values specified in the main `phoenix_lxc_configs.json`.
LXC_ID="956"
LXC_NAME="openWebUIBase"
OPENWEBUI_PORT="8080"
OLLAMA_API_IP="10.0.0.155"
OLLAMA_API_PORT="11434"
OPENWEBUI_DATA_VOLUME="openwebui-data"

# =====================================================================================
# Function: check_docker_installation
# Description: Verifies that the Docker engine is installed and accessible.
#              This is a critical prerequisite for running the Open WebUI container.
# Arguments: None
# Returns: Exits with status 1 if Docker is not found.
# =====================================================================================
check_docker_installation() {
    echo "Checking for Docker installation..."
    if ! command -v docker > /dev/null; then
        echo "Docker is not installed. This script requires Docker. Please ensure the 'docker' feature is enabled for this LXC." >&2
        exit 1
    fi
    echo "Docker is installed."
}

# =====================================================================================
# Function: pull_openwebui_image
# Description: Pulls the latest official Open WebUI Docker image from the GitHub Container Registry.
#              Ensures the container uses the most recent stable version of the application.
# Arguments: None
# Returns: None. Exits on failure due to `set -e`.
# =====================================================================================
pull_openwebui_image() {
    echo "Pulling the official Open WebUI Docker image..."
    docker pull ghcr.io/open-webui/open-webui:main
}

# =====================================================================================
# Function: create_data_volume
# Description: Creates a named Docker volume to persist Open WebUI data.
#              This ensures that user settings, chat history, and other data are not lost
#              if the container is removed or recreated.
# Arguments: None (uses global OPENWEBUI_DATA_VOLUME)
# Returns: None. Exits on failure.
# =====================================================================================
create_data_volume() {
    echo "Creating persistent volume for Open WebUI data: ${OPENWEBUI_DATA_VOLUME}"
    docker volume create ${OPENWEBUI_DATA_VOLUME}
}

# =====================================================================================
# Function: stop_and_remove_existing_container
# Description: Ensures a clean state by stopping and removing any previously existing
#              Open WebUI container. This makes the script idempotent.
#              The '|| true' construct prevents the script from exiting if the container
#              does not exist on the first run.
# Arguments: None
# Returns: None
# =====================================================================================
stop_and_remove_existing_container() {
    echo "Stopping and removing any existing Open WebUI container to ensure a fresh start..."
    docker stop open-webui || true
    docker rm open-webui || true
}

# =====================================================================================
# Function: start_openwebui_container
# Description: Starts the Open WebUI Docker container with all necessary configurations.
#              This includes port mapping, volume mounting, restart policy, and crucially,
#              the environment variable to connect to the backend Ollama API.
# Arguments: None (uses global configuration variables)
# Returns: None. Exits on failure.
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
    echo "Open WebUI container started."
}

# =====================================================================================
# Function: perform_health_check
# Description: Verifies that the Open WebUI container has started successfully and is
#              accessible. It waits for a short period to allow the service to initialize
#              before attempting a connection.
# Arguments: None (uses global configuration variables)
# Returns: Exits with status 1 if the health check fails.
# =====================================================================================
perform_health_check() {
    echo "Performing health check on Open WebUI..."
    # A delay is necessary to give the web server inside the container time to start.
    sleep 30

    # Use curl to check if the web interface is responding on the configured port.
    if curl -s http://localhost:${OPENWEBUI_PORT} > /dev/null; then
        echo "Health check successful: Open WebUI is accessible at http://$(hostname -I | awk '{print $1}'):${OPENWEBUI_PORT}"
        echo "Open WebUI is configured to connect to the Ollama API at http://${OLLAMA_API_IP}:${OLLAMA_API_PORT}"
    else
        echo "Health check failed: Open WebUI is not accessible." >&2
        echo "Dumping container logs for debugging:" >&2
        docker logs open-webui
        exit 1
    fi
}

# =====================================================================================
# Function: main
# Description: The main entry point for the script. It orchestrates the sequence of
#              setup steps required to deploy the Open WebUI service.
# Arguments: All script arguments are passed to this function.
# Returns: Exits with status 0 on success, or a non-zero status on failure.
# =====================================================================================
main() {
    echo "Starting setup for Open WebUI in LXC ${LXC_ID}: ${LXC_NAME}"

    check_docker_installation
    pull_openwebui_image
    create_data_volume
    stop_and_remove_existing_container
    start_openwebui_container
    perform_health_check

    echo "Setup for LXC ${LXC_ID}: ${LXC_NAME} completed successfully."
}

# Execute the main function, passing all script arguments to it.
main "$@"