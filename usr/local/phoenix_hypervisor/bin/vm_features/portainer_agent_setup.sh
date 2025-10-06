#!/bin/bash
# File: portainer_agent_setup.sh
# Description: This script automates the deployment of the Portainer agent.

set -e

LOG_FILE="/var/log/phoenix_feature_portainer_agent.log"
exec &> >(tee -a "$LOG_FILE")

echo "--- Starting Portainer Agent Deployment ---"

# --- Firewall Configuration ---
echo "Configuring firewall for Portainer agent..."
if ! command -v ufw &> /dev/null; then
    echo "Installing ufw (Uncomplicated Firewall)..."
    apt-get update
    if ! apt-get install -y ufw; then
        echo "Error: Failed to install ufw." >&2
        exit 1
    fi
fi
echo "Allowing incoming traffic on port 9001..."
ufw allow 9001/tcp
echo "Enabling the firewall..."
echo "y" | ufw enable
echo "Firewall configured."

# --- Get VM Name from Context ---
CONTEXT_FILE="/persistent-storage/.phoenix_scripts/vm_context.json"
echo "Checking for context file at: $CONTEXT_FILE"
if [ ! -f "$CONTEXT_FILE" ]; then
    echo "Error: VM context file not found at $CONTEXT_FILE" >&2
    ls -l /persistent-storage/.phoenix_scripts/
    exit 1
fi

echo "Context file found. Contents:"
cat "$CONTEXT_FILE"

VM_NAME=$(jq -r '.name' "$CONTEXT_FILE")
if [ -z "$VM_NAME" ] || [ "$VM_NAME" == "null" ]; then
    echo "Error: Could not extract VM name from context file. jq output was empty or null." >&2
    exit 1
fi

# --- Idempotency: Ensure old container is removed ---
if [ "$(docker ps -a -q -f name=$VM_NAME)" ]; then
    echo "Found existing container named $VM_NAME. Stopping and removing it..."
    docker stop "$VM_NAME"
    docker rm "$VM_NAME"
    echo "Old container removed."
else
    echo "No existing container named $VM_NAME found."
fi


echo "Successfully extracted VM_NAME: $VM_NAME"
echo "Setting Portainer agent name to: $VM_NAME"

if ! docker run -d \
  -p 9001:9001 \
  --name "$VM_NAME" \
  --hostname "$VM_NAME" \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  portainer/agent -H tcp://0.0.0.0:9001 --no-tls; then
    echo "Error: Failed to start Portainer agent." >&2
    exit 1
fi

echo "Agent container started. Waiting for agent to become responsive..."
attempts=0
max_attempts=12 # 2 minutes
interval=10
while [ $attempts -lt $max_attempts ]; do
    if curl -s "http://localhost:9001/ping" | grep -q "OK"; then
        echo "Portainer agent is responsive."
        break
    fi
    echo "Agent not yet responsive. Retrying in $interval seconds... (Attempt $((attempts + 1))/$max_attempts)"
    sleep $interval
    attempts=$((attempts + 1))
done

if [ $attempts -eq $max_attempts ]; then
    echo "Error: Portainer agent did not become responsive." >&2
    docker logs "$VM_NAME"
    exit 1
fi

echo "--- Portainer Agent Logs ---"
docker logs "$VM_NAME"
echo "--------------------------"

echo "--- Portainer Agent Deployment Complete ---"