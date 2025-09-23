#!/bin/bash
# check_vllm.sh
# This script checks the health of the vLLM service.

# Check if a process is listening on port 8000
if ! lsof -i:8000 -sTCP:LISTEN -t >/dev/null; then
    echo "Error: No process is listening on port 8000."
    exit 1
fi

# Check if the API is responsive
if ! curl --fail --silent http://localhost:8000/health > /dev/null; then
    echo "Error: vLLM API is not responding."
    exit 1
fi

echo "Success: vLLM is healthy."
exit 0