#!/bin/bash
# check_n8n.sh
# This script checks the health of the n8n service.

# Check if a process is listening on port 5678
if ! lsof -i:5678 -sTCP:LISTEN -t >/dev/null; then
    echo "Error: No process is listening on port 5678."
    exit 1
fi

# Check if the API is responsive
if ! curl --fail --silent http://localhost:5678/healthz > /dev/null; then
    echo "Error: n8n API is not responding."
    exit 1
fi

echo "Success: n8n is healthy."
exit 0