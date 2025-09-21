#!/bin/bash
# check_qdrant.sh
# This script checks the health of the Qdrant service.

# Check if the API is responsive via Nginx
if ! curl --fail --silent http://10.0.0.153/qdrant/healthz > /dev/null; then
    echo "Error: Qdrant API is not responding via Nginx."
    exit 1
fi

echo "Success: Qdrant is healthy."
exit 0