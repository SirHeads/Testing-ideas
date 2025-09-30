#!/bin/bash
#
# File: phoenix_hypervisor_lxc_952.sh
# Description: This script configures and launches the Qdrant vector database within LXC container 952.
#              It serves as the final application-specific step in the orchestration process for this container.
#              The script ensures that the Qdrant Docker container is always running, providing a high-performance
#              vector search service for AI applications, particularly for Retrieval-Augmented Generation (RAG) tasks.
#
# Dependencies: - A running Docker service within the container.
#               - The `phoenix_hypervisor_common_utils.sh` script for logging and configuration functions.
#               - The main `phoenix_orchestrator.sh` script, which calls this script.
#
# Inputs: - CTID (Container ID): Implicitly 952, as defined in the `phoenix_lxc_configs.json`.
#         - Configuration: Reads port mappings from `phoenix_lxc_configs.json` for container 952.
#
# Outputs: - A running Docker container named "qdrant" hosting the Qdrant vector database service.
#          - The service will be accessible on the ports defined in the configuration.

# --- Determine script's absolute directory ---
# This ensures that sourced scripts and other resources are found reliably, regardless of where this script is called from.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
# Imports shared functions for logging (e.g., log_info) and reading JSON configuration (jq_get_value).
source "${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
# Defines constants for the Docker image, container name, and network to improve readability and maintainability.
QDRANT_IMAGE="qdrant/qdrant:latest"
QDRANT_CONTAINER_NAME="qdrant"
DOCKER_NETWORK_NAME="qdrant_network"

# --- Main Logic ---
log_info "Starting Qdrant container setup for LXC 952..."

# Check if the dedicated Docker network for Qdrant exists.
# Using a dedicated network improves isolation and allows containers to communicate using DNS.
if ! docker network ls | grep -q "$DOCKER_NETWORK_NAME"; then
    log_info "Creating Docker network: $DOCKER_NETWORK_NAME"
    docker network create "$DOCKER_NETWORK_NAME"
fi

# Check if a container with the same name is already running or exists.
# This makes the script idempotent, ensuring a clean state before starting a new container.
if docker ps -a --format '{{.Names}}' | grep -q "^${QDRANT_CONTAINER_NAME}$"; then
    log_info "Qdrant container is already running or exists. Stopping and removing it to ensure a fresh start."
    docker stop "$QDRANT_CONTAINER_NAME"
    docker rm "$QDRANT_CONTAINER_NAME"
fi

# Pull the latest version of the Qdrant image from Docker Hub.
# This ensures the container is always running the most up-to-date stable version.
log_info "Pulling latest Qdrant image: $QDRANT_IMAGE"
docker pull "$QDRANT_IMAGE"

# Dynamically construct port mapping arguments for the `docker run` command.
# This reads the desired port configurations from the central `phoenix_lxc_configs.json` file.
log_info "Reading port mappings from configuration for container 952."
port_mappings=$(jq_get_value "952" ".ports[]")
port_args=""
for mapping in $port_mappings; do
    port_args="$port_args -p $mapping"
done

# Start the new Qdrant Docker container with the specified configurations.
# --restart always: Ensures the container automatically restarts if it crashes or the system reboots.
# --network: Attaches the container to the dedicated network.
log_info "Starting new Qdrant container..."
log_info "Executing docker run command with the following arguments:"
log_info "docker run -d --restart always --network $DOCKER_NETWORK_NAME $port_args --name \"$QDRANT_CONTAINER_NAME\" \"$QDRANT_IMAGE\""
docker run -d --restart always \
    --network "$DOCKER_NETWORK_NAME" \
    $port_args \
    --name "$QDRANT_CONTAINER_NAME" \
    "$QDRANT_IMAGE"

# Confirm completion of the script.
log_info "Qdrant container started successfully."
exit_script 0