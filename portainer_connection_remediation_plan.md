# Remediation Plan: Portainer Connection Failure

## 1. Problem Analysis

The `phoenix sync all` command is failing at the Portainer authentication stage due to a TLS certificate validation error. The `portainer-manager.sh` script is attempting to connect to the Portainer API via the Nginx gateway using its IP address (`10.0.0.153`). However, the certificate served by Nginx is only valid for the hostname `nginx.internal.thinkheads.ai`. This mismatch causes a Subject Alternative Name (SAN) verification failure, and the connection is terminated.

## 2. Proposed Solution

The solution is to modify the `portainer-manager.sh` script to use the correct hostname when connecting to the Portainer API. This will ensure that the TLS certificate matches the requested hostname, and the connection will be established successfully.

Specifically, we will change the `get_portainer_jwt` function to connect to `portainer.internal.thinkheads.ai` and resolve it to the Nginx gateway's IP address.

## 3. Implementation Steps

1.  **Modify `get_portainer_jwt`:**
    *   Update the `JWT_RESPONSE` variable to use the `--resolve` flag with `curl`. This will force `curl` to use the correct IP address for the hostname, bypassing any potential DNS issues.

2.  **Switch to Code Mode:** Request a switch to the `code` persona to apply the necessary changes to the `portainer-manager.sh` script.

## 4. Validation

After the fix is applied, the user will re-run the `phoenix sync all` command. We will monitor the output to confirm that the Portainer authentication succeeds and the `sync` process continues to completion.