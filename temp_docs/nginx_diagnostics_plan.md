# Nginx Gateway Diagnostics Plan

This plan outlines the steps to diagnose and verify the Nginx gateway running in LXC 101.

## Objective

To ensure that Nginx is correctly configured, can communicate with the backend Traefik proxy (LXC 102), and is properly terminating TLS connections using the certificates provided by Step-CA.

## Verification Steps

### 1. Verify Nginx Service and Configuration (LXC 101)

*   **Check the Nginx service status:**
    ```bash
    pct exec 101 -- systemctl status nginx
    ```
*   **View the Nginx error logs for any obvious issues:**
    ```bash
    pct exec 101 -- journalctl -u nginx -n 50 --no-pager
    ```
*   **Inspect the final, deployed Nginx site configuration:**
    ```bash
    pct exec 101 -- cat /etc/nginx/sites-enabled/gateway
    ```
*   **Run the Nginx configuration test to validate syntax:**
    ```bash
    pct exec 101 -- nginx -t
    ```

### 2. Verify Connectivity to Backend (Traefik)

These commands test the network path from the Nginx container to the Traefik container.

*   **Test DNS resolution of the Traefik container:**
    ```bash
    pct exec 101 -- dig traefik-internal.internal.thinkheads.ai
    ```
    *   **Note:** The hostname might differ based on the `traefik_service` name in the config. The key is to verify that Nginx can resolve the backend's name to the correct IP (10.0.0.12).

*   **Test network connectivity to Traefik's HTTP port:**
    ```bash
    # nc (netcat) should be installed for this. If not, use curl.
    pct exec 101 -- nc -zv 10.0.0.12 80
    ```
    *   **Alternative using curl:**
        ```bash
        pct exec 101 -- curl -v http://10.0.0.12
        ```

### 3. Verify External TLS and Connectivity

These commands test the full path from the Proxmox host to a backend service through the Nginx and Traefik proxies.

*   **Test the Portainer API endpoint through the gateway:**
    ```bash
    # This command uses curl with --resolve to bypass public DNS and test the internal path.
    # It also uses --cacert to trust our internal CA.
    curl --resolve portainer.internal.thinkheads.ai:443:10.0.0.153 \
         --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt \
         https://portainer.internal.thinkheads.ai/api/system/status
    ```
    *   **Expected Output:** A JSON response from the Portainer API (e.g., `{"Status":"No administrator account found"}` on a fresh install, or the instance ID).

*   **Inspect the certificate presented by the gateway:**
    ```bash
    openssl s_client -connect 10.0.0.153:443 -servername portainer.internal.thinkheads.ai < /dev/null 2>/dev/null | openssl x509 -noout -text
    ```
    *   **Expected Output:** The details of the TLS certificate for `portainer.internal.thinkheads.ai`, issued by "ThinkHeads Internal CA". Check the validity dates.

## Expected Outcomes

*   The Nginx service is active and running without errors.
*   The Nginx configuration is valid and points to the correct backend service for Traefik.
*   The Nginx container can resolve and connect to the Traefik container on port 80.
*   The `curl` command to the Portainer API through the gateway succeeds and returns a valid JSON response.
*   The `openssl` command shows that the gateway is presenting the correct, valid TLS certificate.

Failures in these steps will help pinpoint issues in the Nginx configuration, firewall rules between the containers, or the TLS certificate setup.