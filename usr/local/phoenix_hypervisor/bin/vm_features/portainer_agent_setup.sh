#!/bin/bash

# Log output to file
exec > >(tee -a /var/log/phoenix_feature_portainer_agent.log) 2>&1
echo "--- Starting Portainer Agent Deployment ---"

# Load VM context
CONTEXT_FILE="/persistent-storage/.phoenix_scripts/vm_context.json"
if [ ! -f "$CONTEXT_FILE" ]; then
    echo "Error: Context file not found at: $CONTEXT_FILE"
    exit 1
fi
echo "Checking for context file at: $CONTEXT_FILE"
echo "Context file found. Contents:"
cat "$CONTEXT_FILE"

# Extract VM_NAME and AGENT_PORTAINER_URL
VM_NAME=$(jq -r '.name' "$CONTEXT_FILE")
if [ -z "$VM_NAME" ]; then
    echo "Error: Could not extract VM_NAME from context file"
    exit 1
fi
echo "Successfully extracted VM_NAME: $VM_NAME"
echo "Setting Portainer agent name to: $VM_NAME"
echo "Setting AGENT_PORTAINER_URL to: https://10.0.0.101:9443"

# Configure firewall
echo "Configuring firewall for Portainer agent..."
echo "Allowing incoming traffic on port 9001..."
ufw allow 9001 || echo "Skipping adding existing rule"
ufw allow 9001 comment 'Portainer Agent' || echo "Skipping adding existing rule (v6)"
echo "Enabling the firewall..."
ufw --force enable
echo "Firewall configured."

# Check if container is already running
if docker ps -a --filter "name=$VM_NAME" | grep -q "$VM_NAME"; then
    echo "Portainer agent container '$VM_NAME' is already running."
    echo "Performing a quick health check..."
    if curl -k -s -o /dev/null -w "%{http_code}" "https://127.0.0.1:9001/ping" -v | grep -q "204"; then
        echo "Portainer agent is responsive. No action needed."
        exit 0
    else
        echo "Agent is running but not healthy. Proceeding to recreate it."
        docker stop "$VM_NAME"
        docker rm "$VM_NAME"
    fi
else
    echo "No existing container named $VM_NAME found. Proceeding with creation."
fi

# Start the Portainer agent container
docker run -d --name "$VM_NAME" \
    -p 9001:9001 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /var/lib/docker/volumes:/var/lib/docker/volumes \
    --env AGENT_PORTAINER_URL=https://10.0.0.101:9443 \
    --env AGENT_INSECURE_POLL=true \
    --env AGENT_LOG_LEVEL=DEBUG \
    portainer/agent:latest

if [ $? -ne 0 ]; then
    echo "Error: Failed to start Portainer agent container"
    exit 1
fi

echo "Agent container started. Waiting for agent to become responsive..."

# Health check with retries
max_attempts=20
interval=10
attempts=0

while [ $attempts -lt $max_attempts ]; do
    if curl -k -s -o /dev/null -w "%{http_code}" "https://127.0.0.1:9001/ping" -v | grep -q "204"; then
        echo "Portainer agent is responsive."
        break
    fi
    echo "Agent not yet responsive. Retrying in $interval seconds... (Attempt $((attempts + 1))/$max_attempts)"
    sleep $interval
    attempts=$((attempts + 1))
done

if [ $attempts -ge $max_attempts ]; then
    echo "Error: Portainer agent did not become responsive."
    exit 1
fi

echo "Portainer agent setup completed successfully."
exit 0