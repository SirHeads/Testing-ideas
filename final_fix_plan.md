# Final Fix Plan: Resolving the Nginx to Traefik Routing Issue

## 1. Problem Diagnosis

After a thorough review of the system status and live configurations, we have identified the root cause of the `404 page not found` error when trying to access services like the Portainer and Traefik dashboards.

- **Core Issue:** A protocol mismatch exists between the Nginx gateway (LXC 101) and the Traefik service mesh (LXC 102).
- **Nginx Behavior:** Nginx is configured to terminate the external SSL connection and then re-encrypt the traffic before forwarding it to Traefik (`proxy_pass https://10.0.0.12:443`).
- **Traefik Expectation:** Traefik's routers are configured to use the `web` entrypoint, which is set up to listen for unencrypted HTTP traffic on port 80, not HTTPS on port 443.

This conflict means that Traefik receives an encrypted request on a port where it expects plain text, causing it to reject the connection, which results in Nginx returning a `404`.

## 2. Proposed Solution

The correct architectural pattern is for Nginx to handle all SSL termination and then forward decrypted traffic to the internal service mesh. To implement this, we will modify the Nginx configuration generator script.

**The Fix:**

The change will be applied to the `generate_nginx_config.sh` script. We will modify the `proxy_pass` directive to:

1.  Use the `http` protocol instead of `https`.
2.  Target port `80` on the Traefik container, which corresponds to the `web` entrypoint.

**Example Change (to be applied to all generated `server` blocks):**

```diff
-        proxy_pass https://10.0.0.12:443;
+        proxy_pass http://10.0.0.12:80;
```

This ensures that Nginx forwards a plain HTTP request, which Traefik's `web` entrypoint can correctly process and route to the appropriate backend service based on the `Host` header.

## 3. Implementation and Verification

The implementation will be carried out by the **Code** mode, which will:

1.  Modify the [`usr/local/phoenix_hypervisor/bin/generate_nginx_config.sh`](usr/local/phoenix_hypervisor/bin/generate_nginx_config.sh) script to implement the change described above.
2.  Execute `phoenix sync all` to regenerate the Nginx configuration with the fix and reload the service.
3.  Run the [`get_system_status.sh`](get_system_status.sh) script again to verify that the `curl` command now succeeds and the system is fully operational.
