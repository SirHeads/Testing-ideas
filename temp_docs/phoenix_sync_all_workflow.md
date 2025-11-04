# Phoenix Sync All Workflow Documentation

This document outlines the step-by-step process executed by the `phoenix sync all` command.

## 1. Initialization

- The `phoenix-cli` script receives the `sync all` command.
- The command is dispatched to the `portainer-manager.sh` script for execution.

## 2. Core Infrastructure Synchronization

The `portainer-manager.sh` script begins by synchronizing the foundational components of the hypervisor environment.

- **Trusted CA:** Ensures the Proxmox host's certificate store includes the root CA certificate from the Step-CA container (LXC 103).
- **DNS Configuration:** Executes `hypervisor_feature_setup_dns_server.sh` to:
    - Aggregate DNS records from all LXC, VM, and Docker stack configurations.
    - Generate a new `dnsmasq` configuration file.
    - Restart the `dnsmasq` service on the hypervisor.
- **Firewall Rules:** Executes `hypervisor_feature_setup_firewall.sh` to:
    - Aggregate firewall rules from the global, LXC, and VM configurations.
    - Generate a new Proxmox firewall configuration file (`/etc/pve/firewall/cluster.fw`).
    - Restart the `pve-firewall` service.
- **Certificate Management:** Executes `certificate-renewal-manager.sh` to:
    - Read the `certificate-manifest.json`.
    - Check the validity of each certificate.
    - Renew any expired or soon-to-expire certificates using the Step-CA.
    - Execute any post-renewal commands (e.g., restarting services).

## 3. Portainer Deployment and Verification

- The script identifies all VMs with a `portainer_role` defined (`primary` or `agent`).
- **Portainer Server (VM 1001):**
    - Ensures the TLS certificates for the Portainer UI are valid, renewing them if necessary.
    - Creates an NFS-backed Docker volume for Portainer's persistent data.
    - Deploys the Portainer server container using a `docker-compose.yml` file stored on the NFS share.
    - Waits for the Portainer API to become available and sets up the initial admin user.
- **Portainer Agent (VM 1002):**
    - Deploys the Portainer agent container using `docker run`.
    - Performs a health check to ensure the agent is responsive.

## 4. Service Mesh and Gateway Configuration

- **Traefik (LXC 102):**
    - Executes `generate_traefik_config.sh` to create a dynamic configuration file (`dynamic_conf.yml`). This file defines HTTP routers and services based on the `traefik_service` definitions in the LXC and VM configuration files.
    - Pushes the generated configuration to the Traefik container.
    - Reloads the Traefik service to apply the new configuration.
- **Nginx (LXC 101):**
    - Executes `generate_nginx_gateway_config.sh` to create the main gateway configuration. This configuration handles TLS termination for all external traffic and proxies it to the Traefik container.
    - Pushes the generated configuration to the Nginx container.
    - Reloads the Nginx service.

## 5. Stack Synchronization

- **Authentication:** Obtains a JSON Web Token (JWT) from the Portainer API.
- **Endpoint Registration:** Calls `sync_portainer_endpoints` to ensure the Portainer server is aware of the agent environment running on VM 1002.
- **Stack Discovery:** Scans the `/usr/local/phoenix_hypervisor/stacks` directory to find all available Docker stacks.
- **Stack Deployment:** For each VM with `docker_stacks` defined:
    - Identifies the correct Portainer endpoint ID for the VM.
    - For each stack assigned to the VM, it calls the `sync_stack` function.
    - The `sync_stack` function:
        - Prepares the `docker-compose.yml` on the shared NFS volume.
        - Injects any required Traefik labels into the compose file.
        - Uses the Portainer API to create or update the stack in the target endpoint, passing the path to the compose file on the NFS share.
