#!/bin/bash
#
# File: phoenix_hypervisor_lxc_952.sh
# Description: Application script for LXC 952. Starts the Qdrant Docker container
#              using container-native Docker commands.

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
source "${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
QDRANT_IMAGE="qdrant/qdrant:latest"
QDRANT_CONTAINER_NAME="qdrant"
DOCKER_NETWORK_NAME="qdrant_network"

# --- Main Logic ---
log_info "Starting Qdrant container..."

# Check if the network exists
if ! docker network ls | grep -q "$DOCKER_NETWORK_NAME"; then
    log_info "Creating Docker network: $DOCKER_NETWORK_NAME"
    docker network create "$DOCKER_NETWORK_NAME"
fi

# Check if a container with the same name is already running
if docker ps -a --format '{{.Names}}' | grep -q "^${QDRANT_CONTAINER_NAME}$"; then
    log_info "Qdrant container is already running or exists. Restarting..."
    docker stop "$QDRANT_CONTAINER_NAME"
    docker rm "$QDRANT_CONTAINER_NAME"
fi

log_info "Pulling latest Qdrant image..."
docker pull "$QDRANT_IMAGE"

log_info "Starting new Qdrant container..."
log_info "Executing docker run command:"
port_mappings=$(jq_get_value "952" ".ports[]")
port_args=""
for mapping in $port_mappings; do
    port_args="$port_args -p $mapping"
done
log_info "docker run -d --rm --network $DOCKER_NETWORK_NAME $port_args --name \"$QDRANT_CONTAINER_NAME\" \"$QDRANT_IMAGE\""
docker run -d --rm \
    --network "$DOCKER_NETWORK_NAME" \
    $port_args \
    --name "$QDRANT_CONTAINER_NAME" \
    "$QDRANT_IMAGE"

log_info "Qdrant container started successfully."
exit_script 0