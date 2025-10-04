#!/bin/bash
# File: portainer_agent_setup.sh
# Description: This script automates the deployment of the Portainer agent.

set -e

LOG_FILE="/var/log/phoenix_feature_portainer_agent.log"
exec &> >(tee -a "$LOG_FILE")

echo "--- Starting Portainer Agent Deployment ---"

if ! docker run -d \
  -p 9001:9001 \
  --name portainer_agent \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  portainer/agent; then
    echo "Error: Failed to start Portainer agent." >&2
    exit 1
fi

echo "--- Portainer Agent Deployment Complete ---"