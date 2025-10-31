# ACME Challenge Fix Implementation Plan

This document outlines the steps to fix the ACME challenge routing issue.

## 1. Objective

The goal is to modify the Nginx configuration generation script to correctly proxy ACME challenge requests to the Traefik container, allowing the Step CA to successfully validate domain control and issue certificates.

## 2. Implementation Steps

1.  **Apply Proposed Changes**: Modify the `usr/local/phoenix_hypervisor/bin/generate_nginx_gateway_config.sh` script as detailed in the `nginx_config_update_proposal.md` file. This will be done in **Code Mode**.

2.  **Re-run `phoenix sync all`**: Execute the `phoenix sync all` command. This will:
    *   Trigger the updated `generate_nginx_gateway_config.sh` script, creating the corrected Nginx configuration.
    *   Push the new configuration to the Nginx container (ID 101).
    *   Reload the Nginx service to apply the changes.
    *   Trigger a re-sync of the Traefik configuration, which will re-initiate the certificate request process with the Step CA.

3.  **Verify the Fix**: After the `sync` command completes, we will verify the fix by:
    *   Checking the Traefik logs for successful certificate acquisition.
    *   Inspecting the TLS certificates for the services in a browser to confirm they are issued by our internal CA.

## 3. Execution Mode

This plan will be executed in **Code Mode** to allow for the necessary file modifications and command execution.