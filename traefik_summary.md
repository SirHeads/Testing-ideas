# Traefik Integration Verification Commands

## Objective
Verify that Traefik has successfully discovered and configured the Portainer service from VM 1001.

## Commands to be executed on the Proxmox Host

1.  **Query Traefik API for Portainer Service:**
    *   **Purpose:** This command enters the Traefik container (LXC 102) and uses `curl` to query the Traefik API. It then uses `jq` to filter for the Portainer service and checks if its server address is correctly set to the IP of VM 1001.
    *   **Command:**
        ```bash
        pct exec 102 -- bash -c "curl -s http://127.0.0.1:8080/api/http/services | jq -e '.[] | select(.name == \"portainer@file\" and .serverStatus.[\"https://10.0.0.101:9443\"] == \"UP\")'" && echo "SUCCESS: Traefik has discovered and configured the Portainer service correctly." || echo "FAILURE: Traefik has not discovered the Portainer service or it is misconfigured."
        ```

2.  **Check Traefik Logs for Errors:**
    *   **Purpose:** Reviews the Traefik logs for any errors related to the Portainer service, such as certificate issues or connection problems.
    *   **Command:**
        ```bash
        pct exec 102 -- journalctl -u traefik.service --no-pager | grep "portainer" | grep "error" && echo "FAILURE: Errors found in Traefik logs related to Portainer." || echo "SUCCESS: No errors found in Traefik logs for Portainer."