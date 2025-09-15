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

# --- Main Logic ---
log_info "Starting Qdrant container..."

# Check if a container with the same name is already running
if docker ps -a --format '{{.Names}}' | grep -q "^${QDRANT_CONTAINER_NAME}$"; then
    log_info "Qdrant container is already running or exists. Restarting..."
    docker stop "$QDRANT_CONTAINER_NAME"
    docker rm "$QDRANT_CONTAINER_NAME"
fi

log_info "Pulling latest Qdrant image..."
docker pull "$QDRANT_IMAGE"

log_info "Starting new Qdrant container..."
docker run -d --rm \
    -p 6333:6333 \
    -p 6334:6334 \
    --name "$QDRANT_CONTAINER_NAME" \
    "$QDRANT_IMAGE"

log_info "Qdrant container started successfully."
exit_script 0