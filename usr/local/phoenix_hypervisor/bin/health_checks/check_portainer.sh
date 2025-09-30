#!/bin/bash
#
# File: check_portainer.sh
#
# Description: This script performs a health check on the Portainer service. It
#              verifies that the service is listening on its HTTPS port (9443) and
#              that its web interface is responsive. This check is vital for
#              ensuring the Docker management UI is available.
#
# Dependencies: - The Portainer service must be running.
#               - `lsof` and `curl` commands must be available.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if the Portainer service is healthy.
#   - Exits with status 1 and prints an error message if the service is not
#     listening on the port or if the API is unresponsive.
#   - Console output indicates success or the specific nature of the failure.
#

# --- Health Check Logic ---

# Verify that a process is actively listening on the standard Portainer HTTPS port (9443).
# This confirms that the Portainer server process has started and bound to the correct port.
if ! lsof -i:9443 -sTCP:LISTEN -t >/dev/null; then
    echo "Error: No process is listening on port 9443. The Portainer service may be down or misconfigured."
    exit 1
fi

# Check if the Portainer web interface is responsive.
# A successful response confirms that the web server is running.
# The -k flag is used to allow insecure connections, as Portainer often uses
# a self-signed SSL certificate by default.
# The --fail flag ensures curl exits with an error on non-200 responses.
if ! curl --fail --silent -k https://localhost:9443/ > /dev/null; then
    echo "Error: The Portainer API is not responding. The service may be unhealthy or stuck."
    exit 1
fi

# If both checks pass, the service is considered healthy.
echo "Success: Portainer is healthy."
exit 0