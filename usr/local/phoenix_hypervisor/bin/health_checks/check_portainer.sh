#!/bin/bash
# check_portainer.sh
# This script checks the health of the Portainer service.

# Check if a process is listening on port 9443
if ! lsof -i:9443 -sTCP:LISTEN -t >/dev/null; then
    echo "Error: No process is listening on port 9443."
    exit 1
fi

# Check if the API is responsive (using -k for self-signed certs)
if ! curl --fail --silent -k https://localhost:9443/ > /dev/null; then
    echo "Error: Portainer API is not responding."
    exit 1
fi

echo "Success: Portainer is healthy."
exit 0