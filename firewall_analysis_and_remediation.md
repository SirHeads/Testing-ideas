# Phoenix Hypervisor Network Remediation

## 1. Problem Description

The `phoenix sync all` command was failing with a timeout error during the end-to-end connectivity test. The logs indicated that the Portainer container was in a "zombie" state and could not be restarted, which prevented the Portainer API from becoming available.

## 2. Diagnostic Steps

1.  **Initial Log Analysis:** The initial logs showed that the `portainer_server` container was in a "zombie" state and could not be killed. This prevented the Portainer service from restarting and caused the `curl` command to time out.
2.  **Configuration Review:** I examined the `phoenix_hypervisor_config.json`, `phoenix_lxc_configs.json`, and `phoenix_vm_configs.json` files to understand the system's configuration.
3.  **Portainer and Traefik Configuration Analysis:** I reviewed the `docker-compose.yml` for the Portainer service, the Traefik configuration template, and the `phoenix_stacks_config.json` file. This revealed two issues:
    *   The `docker-compose.yml` for the Portainer service was missing the `init: true` parameter, which is necessary to prevent "zombie" processes.
    *   The Traefik labels in `phoenix_stacks_config.json` were referencing a `websecure` entrypoint and an `internal-resolver` that were not defined in the main Traefik configuration.
4.  **Firewall and Network Analysis:** I reviewed the firewall rules and network configuration and found them to be correct. This confirmed that the issue was not with the network, but with the Portainer service itself.
5.  **Live Diagnostics:** I ran a series of diagnostic commands to confirm the status of the Portainer VM, the Docker containers, and the presence of "zombie" processes. This confirmed that the `portainer_server` container was in a "zombie" state.
6.  **Nginx Gateway Analysis:** I examined the Nginx configuration and logs and found that it was correctly proxying traffic to Traefik.
7.  **Traefik Analysis:** I examined the Traefik logs and dynamic configuration and found that it was not correctly configured to handle HTTPS traffic to the Portainer service.
8.  **Traefik Static Configuration Analysis:** I examined the `phoenix_hypervisor_lxc_102.sh` script and found that it was creating a static configuration file for the Traefik dashboard that was causing the `websecure` entrypoint error.

## 3. Root Cause

The root cause of the issue was a misconfiguration in the `phoenix_hypervisor_lxc_102.sh` script. The script was creating a static configuration file for the Traefik dashboard that was causing the `websecure` entrypoint error.

## 4. Solution

1.  **Remove the static dashboard configuration:** The section of the `phoenix_hypervisor_lxc_102.sh` script that creates the `/etc/traefik/dynamic/dashboard.yml` file was removed.
2.  **Correct the `generate_traefik_config.sh` script:** The script was modified to correctly define the `websecure` entrypoint and the `internal-resolver`.
3.  **Add `init: true` to the Portainer `docker-compose.yml`:** This will ensure that the Portainer container runs with an init process that properly handles signals and prevents "zombie" processes.
4.  **Correct the Traefik labels in `phoenix_stacks_config.json`:** The Traefik labels for the Portainer service were updated to use the correct `web` entrypoint and remove the unnecessary TLS resolver.

## 5. Implementation

The following changes were made:

*   **File:** `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_102.sh`
    *   Removed the section that creates the `/etc/traefik/dynamic/dashboard.yml` file.
*   **File:** `usr/local/phoenix_hypervisor/bin/generate_traefik_config.sh`
    *   Added a `serversTransport` for services that use HTTPS, which will allow Traefik to trust the internal CA certificate used by Portainer.
*   **File:** `usr/local/phoenix_hypervisor/stacks/portainer_service/docker-compose.yml`
    *   Add `init: true` to the `portainer` service definition.
*   **File:** `usr/local/phoenix_hypervisor/etc/phoenix_stacks_config.json`
    *   Update the Traefik labels for the `portainer_service` to use the `web` entrypoint and remove the `tls` and `certresolver` labels.
