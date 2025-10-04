#!/bin/bash
# File: portainer_api_setup.sh
# Description: This script automates the deployment of the Portainer server.

set -e

LOG_FILE="/var/log/phoenix_feature_portainer_server.log"
exec &> >(tee -a "$LOG_FILE")

echo "--- Starting Portainer Server Deployment ---"

PERSISTENT_STORAGE="/persistent-storage"
COMPOSE_FILE_PATH="${PERSISTENT_STORAGE}/portainer/docker-compose.yml"

if [ -f "$COMPOSE_FILE_PATH" ]; then
    echo "Found docker-compose.yml at $COMPOSE_FILE_PATH"
    compose_dir=$(dirname "$COMPOSE_FILE_PATH")
    echo "Running 'docker-compose up -d' in $compose_dir"
    if ! (cd "$compose_dir" && docker-compose up -d); then
        echo "Error: Failed to run docker-compose for $COMPOSE_FILE_PATH" >&2
        exit 1
    else
        echo "Successfully started Portainer server from $COMPOSE_FILE_PATH"
    fi
else
    echo "Error: Portainer docker-compose.yml not found at $COMPOSE_FILE_PATH" >&2
    exit 1
fi

echo "--- Portainer Server Deployment Complete ---"