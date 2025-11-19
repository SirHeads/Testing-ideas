# Traefik Docker Fix Plan (with mTLS)

This document outlines the steps to resolve the routing issue between Nginx and Traefik by adopting a secure, double-TLS termination architecture with full mutual TLS (mTLS) for a zero-trust internal network.

## 1. Problem Diagnosis

The root cause of the `404 page not found` error is a protocol mismatch. Nginx is re-encrypting traffic and sending it via HTTPS to a Traefik entrypoint that is only listening for unencrypted HTTP.

## 2. Architectural Solution: Zero-Trust with mTLS

We will implement a full zero-trust model for internal traffic:

1.  **Nginx** will terminate the public TLS connection from the user.
2.  Nginx will then act as a **client**, presenting its own unique certificate to Traefik.
3.  **Traefik** will run a new, private **mTLS entrypoint** that verifies Nginx's client certificate before allowing the connection.
4.  Traefik then terminates the second TLS connection and routes the request to the final backend service.

This ensures that traffic is always encrypted and that only the Nginx gateway is authorized to communicate with the internal service mesh.

## 3. Implementation Steps

The following changes will be made by the **Code** mode:

### Step 3.1: Update Certificate Manifest (`certificate-manifest.json`)

A new entry will be added to `usr/local/phoenix_hypervisor/etc/certificate-manifest.json` to automatically generate and manage a client certificate for Nginx.

```json
{
    "common_name": "nginx-gateway-client",
    "sans": [
        "nginx.internal.thinkheads.ai"
    ],
    "guest_id": 101,
    "guest_type": "lxc",
    "cert_path": "/mnt/pve/quickOS/lxc-persistent-data/101/ssl/nginx-client.crt",
    "key_path": "/mnt/pve/quickOS/lxc-persistent-data/101/ssl/nginx-client.key",
    "owner": "root:root",
    "post_renewal_command": "pct exec 101 -- /bin/bash -c 'mkdir -p /etc/nginx/ssl && mv /tmp/cert.pem /etc/nginx/ssl/nginx-client.crt && mv /tmp/key.pem /etc/nginx/ssl/nginx-client.key && chown root:root /etc/nginx/ssl/nginx-client.* && chmod 640 /etc/nginx/ssl/nginx-client.*'"
}
```

### Step 3.2: Update Firewall Rules (`phoenix_lxc_configs.json` & `phoenix_hypervisor_config.json`)

New rules will be added to the declarative firewall configurations to allow traffic on port `8443` between Nginx and Traefik.

-   **In `phoenix_lxc_configs.json` for LXC 101 (Nginx):**
    ```json
    {
        "type": "out",
        "action": "ACCEPT",
        "proto": "tcp",
        "dest": "10.0.0.12",
        "port": "8443",
        "comment": "Allow Nginx to proxy to Traefik mTLS mesh"
    }
    ```
-   **In `phoenix_lxc_configs.json` for LXC 102 (Traefik):**
    ```json
    {
        "type": "in",
        "action": "ACCEPT",
        "proto": "tcp",
        "source": "10.0.0.153",
        "port": "8443",
        "comment": "Allow Nginx to proxy to Traefik mTLS mesh"
    }
    ```
-   **In `phoenix_hypervisor_config.json` under `global_firewall_rules`:**
    ```json
    {
        "type": "in",
        "action": "ACCEPT",
        "proto": "tcp",
        "source": "10.0.0.153",
        "dest": "10.0.0.12",
        "port": "8443",
        "comment": "Allow Nginx to proxy to Traefik mTLS mesh"
    }
    ```

### Step 3.3: Modify Traefik Static Configuration (`traefik.yml.template`)

The new `mesh` entrypoint in `usr/local/phoenix_hypervisor/etc/traefik/traefik.yml.template` will be configured to require a client certificate signed by our internal CA.

```yaml
entryPoints:
  web:
    address: :80
  websecure:
    address: :443
  mesh:
    address: :8443
    http:
      tls:
        clientCA:
          files:
            - /etc/step-ca/ssl/phoenix_root_ca.crt
          optional: false # Require a client cert
```

### Step 3.4: Modify Traefik Configuration Generator (`generate_traefik_config.sh`)

The script at `usr/local/phoenix_hypervisor/bin/generate_traefik_config.sh` will be updated to modify the dynamically generated router configurations. For every router:

1.  The `entryPoints` will be changed from `web` to `mesh`.
2.  A `tls: {}` block will be added to instruct Traefik to perform TLS termination.

### Step 3.5: Modify Nginx Configuration Generator (`generate_nginx_config.sh`)

The script at `usr/local/phoenix_hypervisor/bin/generate_nginx_config.sh` will be updated to:

1.  Change the `proxy_pass` directive to target the new `mesh` entrypoint on port `8443`.
2.  Add the necessary `proxy_ssl_*` directives to present Nginx's client certificate to Traefik for authentication.

**Change:**

```diff
- proxy_pass https://10.0.0.12:443;
+ proxy_pass https://10.0.0.12:8443;
+ proxy_ssl_certificate     /etc/nginx/ssl/nginx-client.crt;
+ proxy_ssl_certificate_key /etc/nginx/ssl/nginx-client.key;
+ proxy_ssl_verify        on;
+ proxy_ssl_verify_depth  2;
+ proxy_ssl_trusted_certificate /etc/step-ca/ssl/phoenix_root_ca.crt;
```

## 4. Verification

After the code changes are applied, the following steps will be taken to verify the fix:

1.  Run `phoenix sync all`.
2.  Execute the `get_system_status.sh` script.
3.  Confirm that the `curl` command now succeeds, verifying that the full mTLS connection is working correctly.
