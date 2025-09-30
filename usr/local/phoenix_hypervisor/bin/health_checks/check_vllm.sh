#!/bin/bash
#
# File: check_vllm.sh
#
# Description: This script performs a basic health check on the vLLM (Vectorized
#              Large Language Model) service. It verifies that the service is
#              listening on its default port (8000) and that its /health endpoint
#              is responsive. This is a critical check to ensure the LLM is ready
#              to accept inference requests.
#
# Dependencies: - The vLLM service must be running.
#               - `lsof` and `curl` commands must be available.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if the vLLM service is healthy.
#   - Exits with status 1 and prints an error message if the service is not
#     listening on the port or if the API health check fails.
#   - Console output indicates success or the specific nature of the failure.
#

# --- Health Check Logic ---

# Verify that a process is actively listening on the standard vLLM port (8000).
# This is the first confirmation that the vLLM server process has started.
if ! lsof -i:8000 -sTCP:LISTEN -t >/dev/null; then
    echo "Error: No process is listening on port 8000. The vLLM service may be down or misconfigured."
    exit 1
fi

# Perform an API health check by querying the /health endpoint.
# A successful response (HTTP 200) indicates that the vLLM application is running
# and has not encountered a critical error. The --fail flag ensures curl exits
# with an error on non-200 responses.
if ! curl --fail --silent http://localhost:8000/health > /dev/null; then
    echo "Error: The vLLM API is not responding to health checks. The service may be unhealthy or still loading the model."
    exit 1
fi

# If both checks pass, the service is considered healthy.
echo "Success: vLLM is healthy."
exit 0