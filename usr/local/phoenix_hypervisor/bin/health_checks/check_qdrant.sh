#!/bin/bash
#
# File: check_qdrant.sh
#
# Description: This script performs a health check on the Qdrant vector database
#              service. It verifies that the Qdrant API is responsive by querying
#              its health check endpoint (`/healthz`) through the Nginx reverse proxy.
#              This validation is crucial for ensuring the embedding and retrieval
#              capabilities of the AI services are functional.
#
# Dependencies: - The Qdrant service must be running.
#               - The Nginx reverse proxy must be configured to route to Qdrant.
#               - `curl` command must be available.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if the Qdrant service is healthy.
#   - Exits with status 1 and prints an error message if the API health check fails.
#   - Console output indicates success or failure.
#

# --- Health Check Logic ---

# Perform an API health check by querying the /qdrant/healthz endpoint via the Nginx gateway.
# A successful response (HTTP 200) indicates that both Nginx and the backend Qdrant
# service are operational. The --fail flag ensures curl exits with an error on
# non-200 responses.
if ! curl --fail --silent http://10.0.0.153/qdrant/healthz > /dev/null; then
    echo "Error: The Qdrant API is not responding via the Nginx gateway. Check both Nginx and Qdrant services."
    exit 1
fi

# If the check passes, report that the service is healthy.
echo "Success: Qdrant is healthy."
exit 0