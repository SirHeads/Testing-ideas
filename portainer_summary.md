# Portainer API Readiness Verification

## Objective
Verify that the Portainer service is running correctly inside VM 1001 and is ready to accept API calls.

## Commands to be executed inside VM 1001

1.  **Check Docker Container Status:**
    *   **Purpose:** Confirms that the Portainer Docker container is running.
    *   **Command:**
        ```bash
        docker ps --filter "name=portainer" --format "{{.Names}}" | grep -q "portainer" && echo "SUCCESS: Portainer container is running." || echo "FAILURE: Portainer container is not running."
        ```

2.  **Query Local Portainer API Endpoint:**
    *   **Purpose:** This command uses `curl` to connect to the Portainer API endpoint from within the VM. A successful connection, even if it returns an authentication error, proves that the service is up, the TLS certificate is trusted, and the API is responsive.
    *   **Command:**
        ```bash
        curl -sk https://localhost:9443/api/status | jq -e '.status == "UP"' && echo "SUCCESS: Portainer API is up and responsive." || echo "FAILURE: Portainer API is down or unresponsive."