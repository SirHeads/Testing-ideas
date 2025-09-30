#!/bin/bash
#
# File: check_n8n.sh
#
# Description: This script performs a health check on the n8n service. It verifies
#              that the service is listening on its designated port and that its
#              health check endpoint is responsive. This is a crucial check for
#              ensuring the n8n workflow automation service is operational.
#
# Dependencies: - The n8n service must be running.
#               - `lsof` and `curl` commands must be available.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if the n8n service is healthy.
#   - Exits with status 1 and prints an error message if the service is not
#     listening on the port or if the API health check fails.
#   - Console output indicates success or the specific nature of the failure.
#

# --- Health Check Logic ---

# Verify that a process is actively listening on the standard n8n port (5678).
# This is the first step to confirm the service has started successfully.
if ! lsof -i:5678 -sTCP:LISTEN -t >/dev/null; then
    echo "Error: No process is listening on port 5678. The n8n service may be down or misconfigured."
    exit 1
fi

# Perform an API health check by querying the /healthz endpoint.
# A successful response (HTTP 200) indicates that the n8n application is running
# and ready to accept requests. The --fail flag ensures curl exits with an error
# on non-200 responses.
if ! curl --fail --silent http://localhost:5678/healthz > /dev/null; then
    echo "Error: The n8n API is not responding to health checks. The service may be stuck or unhealthy."
    exit 1
fi

# If both checks pass, report that the service is healthy.
echo "Success: n8n is healthy."
exit 0