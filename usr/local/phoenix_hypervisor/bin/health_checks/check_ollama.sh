#!/bin/bash
#
# File: check_ollama.sh
#
# Description: This script performs a health check on the Ollama service. It
#              verifies that the service is listening on its standard port (11434)
#              and that its API is responsive. This check is essential for ensuring
#              the local LLM service is ready to serve models.
#
# Dependencies: - The Ollama service must be running.
#               - `lsof` and `curl` commands must be available.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if the Ollama service is healthy.
#   - Exits with status 1 and prints an error message if the service is not
#     listening on the port or if the API is unresponsive.
#   - Console output indicates success or the specific nature of the failure.
#

# --- Health Check Logic ---

# Verify that a process is actively listening on the standard Ollama port (11434).
# This is a primary check to ensure the Ollama server process has started correctly.
if ! lsof -i:11434 -sTCP:LISTEN -t >/dev/null; then
    echo "Error: No process is listening on port 11434. The Ollama service may be down or misconfigured."
    exit 1
fi

# Check if the Ollama API is responsive by sending a request to its root endpoint.
# A successful response (HTTP 200) confirms that the API server is running and
# capable of handling requests. The --fail flag causes curl to exit with an
# error for non-200 responses.
if ! curl --fail --silent http://localhost:11434/ > /dev/null; then
    echo "Error: The Ollama API is not responding. The service may be initializing, stuck, or unhealthy."
    exit 1
fi

# If both checks pass, the service is considered healthy.
echo "Success: Ollama is healthy."
exit 0