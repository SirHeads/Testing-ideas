#!/bin/bash
# check_qdrant.sh
# This script checks the health of the Qdrant service.

# Check if a process is listening on port 6334
if ! lsof -i:6334 -sTCP:LISTEN -t >/dev/null; then
    echo "Error: No process is listening on port 6334."
    exit 1
fi

# Check if the API is responsive
if ! curl --fail --silent http://localhost:6334/healthz > /dev/null; then
    echo "Error: Qdrant API is not responding."
    exit 1
fi

echo "Success: Qdrant is healthy."
exit 0