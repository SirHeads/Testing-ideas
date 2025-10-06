#!/bin/bash
#
# File: check_qdrant.sh
# Description: This script checks the health of the Qdrant service.

set -e

LOG_FILE="/var/log/phoenix_health_check_qdrant.log"
exec &> >(tee -a "$LOG_FILE")

echo "--- Starting Qdrant Health Check ---"

QDRANT_URL="http://localhost:6333"

echo "Waiting for Qdrant to become available at $QDRANT_URL..."
attempts=0
max_attempts=12 # 2 minutes
interval=10

while [ $attempts -lt $max_attempts ]; do
    if curl -s -f "$QDRANT_URL/healthz" > /dev/null; then
        echo "Qdrant is responsive."
        echo "--- Qdrant Health Check Succeeded ---"
        exit 0
    fi
    echo "Qdrant not yet responsive. Retrying in $interval seconds... (Attempt $((attempts + 1))/$max_attempts)"
    sleep $interval
    attempts=$((attempts + 1))
done

echo "Error: Qdrant did not become responsive." >&2
echo "--- Qdrant Health Check Failed ---"
exit 1