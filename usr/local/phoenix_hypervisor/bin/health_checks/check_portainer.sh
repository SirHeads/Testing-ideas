#!/bin/bash
#
# File: check_portainer.sh
# Description: This script checks the health of the Portainer service via the Nginx gateway.

set -e

LOG_FILE="/var/log/phoenix_health_check_portainer.log"
exec &> >(tee -a "$LOG_FILE")

echo "--- Starting Portainer Health Check ---"

PORTAINER_URL="https://portainer.phoenix.thinkheads.ai/api/status"

echo "Waiting for Portainer to become available at $PORTAINER_URL..."
attempts=0
max_attempts=12 # 2 minutes
interval=10

while [ $attempts -lt $max_attempts ]; do
    if curl -s -k --insecure --head "$PORTAINER_URL" | head -n 1 | grep " 200" > /dev/null; then
        echo "Portainer is responsive."
        echo "--- Portainer Health Check Succeeded ---"
        exit 0
    fi
    echo "Portainer not yet responsive. Retrying in $interval seconds... (Attempt $((attempts + 1))/$max_attempts)"
    sleep $interval
    attempts=$((attempts + 1))
done

echo "Error: Portainer did not become responsive." >&2
echo "--- Portainer Health Check Failed ---"
exit 1