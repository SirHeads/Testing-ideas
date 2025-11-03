# Final Project Plan: Phoenix Hypervisor Network Remediation

## 1. Project Goal

To remediate the systemic network and configuration failures in the Phoenix Hypervisor environment. This will be achieved by redesigning the service mesh architecture to be more robust, secure, and manageable, while retaining the core automation principles of the `phoenix-cli` tool.

## 2. "Why": The Problem Statement

The current two-tiered proxy architecture (Nginx -> Traefik with TLS passthrough) is failing due to a combination of:
*   **Overly Complex TLS Management**: TLS is handled at multiple layers, leading to trust and handshake failures.
*   **Firewall Misconfigurations**: Rules are incorrectly scoped and located, blocking critical communication paths (e.g., ACME challenges, API calls).
*   **Brittle Scripts**: Hardcoded values and incorrect assumptions in management scripts (`portainer-manager.sh`) cause cascading failures.

The result is an unstable system where services cannot communicate, and the core `phoenix-cli sync all` workflow is broken.

## 3. "What": The High-Level Solution

We will transition to a simplified, more secure two-tiered architecture where each component has a clear, distinct role.

*   **Nginx (LXC 101)** will become the sole, authoritative **Gateway**. It will handle all TLS termination for the entire internal network using a single wildcard certificate.
*   **Traefik (LXC 102)** will become a pure **Internal Service Mesh**. It will receive unencrypted HTTP traffic from Nginx and be responsible only for routing that traffic to the correct backend service (VMs, LXCs, Docker containers).
*   **Automation Scripts** will be rewritten to support this new model, removing complexity and hardcoded values.
*   **Firewall Rules** will be corrected and applied at the proper scope to enforce this new, simplified traffic flow.

## 4. "How": The Implementation Plan

This is the sequence of changes that will be made in `code` mode.

### Step 1: Update Core Configuration Files

*   **File to be Changed**: `usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json`
    *   **How**: The firewall rules section will be completely rewritten to match the new, simplified ruleset defined in `technical_specifications_v2.md`. All legacy and misplaced rules will be removed.
*   **File to be Changed**: `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`
    *   **How**: The `traefik_service` definitions will be simplified. The `serversTransport` entries, which were related to inter-service TLS, will be removed.
*   **File to be Changed**: `usr/local/phoenix_hypervisor/etc/traefik/traefik.yml.template`
    *   **How**: The template will be modified to remove the `websecure` (port 8443) entrypoint. Traefik will only listen on `web` (port 80) for proxied traffic and `traefik` (port 8080) for its own API. The certificate resolvers will be simplified as Nginx will now handle all ACME challenges.

### Step 2: Rewrite Automation and Generation Scripts

*   **File to be Changed**: `usr/local/phoenix_hypervisor/bin/generate_nginx_gateway_config.sh`
    *   **How**: This script will be rewritten to generate a much simpler `gateway` file. It will create a single `server` block for port 443 that uses the wildcard certificate (`*.internal.thinkheads.ai`) and proxies all traffic to Traefik (`http://10.0.0.12:80`). It will also include the necessary `location` block for handling ACME challenges on port 80.
*   **File to be Changed**: `usr/local/phoenix_hypervisor/bin/generate_traefik_config.sh`
    *   **How**: This script will be updated to generate a dynamic configuration for **HTTP only**. It will read the `traefik_service` definitions and create routers and services that expect plain HTTP, removing all TLS and certificate resolver logic.
*   **File to be Changed**: `usr/local/phoenix_hypervisor/bin/managers/portainer-manager.sh`
    *   **How**: This script will see significant changes:
        *   The `get_portainer_jwt` function will be modified to make its API call directly to the Nginx gateway's FQDN (`nginx.internal.thinkheads.ai`) without the `--resolve` hack. It will use the system's trusted CA.
        *   The `sync_portainer_endpoints` function will be corrected to register the Portainer Agent without the `TLS` flag, as communication is now internal and unencrypted.

### Step 3: User Execution and Verification

After the changes are applied, you will perform the following actions as planned:

1.  **Cleanup**: Manually delete all `.fw` files from `/etc/pve/firewall/`.
2.  **Teardown**: Run `phoenix delete 1002 1001 9000 102 101 103 900` to destroy the old environment.
3.  **Setup**: Run `phoenix setup` to apply hypervisor-level configurations (like the base firewall policy).
4.  **Create**: Run `phoenix create 900 103 101 102 9000 1001 1002` to build the new infrastructure in the correct, dependency-aware order.
5.  **Sync & Deploy**: Run `phoenix sync all`. This is the final orchestration step that will:
    *   Generate and deploy the new DNS records.
    *   Request the wildcard certificate and place it for Nginx.
    *   Generate and deploy the new Nginx and Traefik configurations.
    *   Deploy the Portainer stack and register the agent.
    *   Deploy all other defined services.

## 5. Expected Outcome

Upon completion, the system will be fully functional. The `portainer-manager.sh` script will execute without errors, certificates will be issued correctly, and all services will be accessible via their hostnames through the secure Nginx gateway. The `phoenix-cli` workflow will be restored to its intended, fully automated state.

This comprehensive plan covers all aspects of the remediation. I am ready to proceed.
