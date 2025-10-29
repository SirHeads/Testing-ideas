# Internal Domain Migration Plan v2: Nginx TLS Termination

## 1. Executive Summary

This plan details the architectural remediation of the Nginx gateway (LXC 101). The current implementation suffers from an inconsistency between its configuration (TCP passthrough) and its supporting scripts (which expect TLS termination). This plan resolves the conflict by formally adopting **TLS termination at the Nginx layer**, which is a more secure, standard, and future-proof architecture.

## 2. Architectural Decision: Nginx as TLS Termination Point

The Nginx gateway will be responsible for:

1.  Terminating TLS for all incoming traffic on port 443 using a certificate from the internal Step-CA.
2.  Proxying the decrypted HTTP traffic to the internal Traefik service mesh on port 80.

This approach provides a clear separation of concerns, simplifies the Traefik configuration, and aligns all scripts with a single, coherent architecture.

## 3. Implementation Plan

### Phase 1: Align Certificate Generation and Health Checks

The certificate name mismatch will be resolved. The standard will be `nginx.internal.thinkheads.ai`, which is more specific and descriptive.

*   **File to Modify:** `usr/local/phoenix_hypervisor/bin/health_checks/check_nginx_gateway.sh`
    *   **Change:** Update the `CERT_PATH` and `KEY_PATH` variables to look for `nginx.internal.thinkheads.ai.crt` and `nginx.internal.thinkheads.ai.key`.

*   **File to Modify:** `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh`
    *   **Change:** No change is needed here, as it already generates the correctly named certificate.

### Phase 2: Reconfigure Nginx for TLS Termination

The Nginx configuration will be updated to perform TLS termination and proxying.

*   **File to Modify:** `usr/local/phoenix_hypervisor/bin/generate_nginx_gateway_config.sh`
    *   **Change:**
        *   Remove the TCP stream (passthrough) configuration.
        *   Create a new `server` block for port 443 that listens for SSL traffic.
        *   Configure this block to use the `nginx.internal.thinkheads.ai` certificate.
        *   Add a `location /` block that proxies all traffic to `http://10.0.0.12:80` (Traefik's web entrypoint).

## 4. Validation

After the changes are applied, the `phoenix setup && phoenix create ...` command should be re-run. The Nginx health check will now pass because:

1.  The application script will correctly generate the `nginx.internal.thinkheads.ai.crt` certificate.
2.  The Nginx configuration will be correctly configured to use it.
3.  The health check will be correctly looking for the `nginx.internal.thinkheads.ai.crt` certificate.

This will resolve the immediate failure and result in a stable, consistent, and well-architected gateway.