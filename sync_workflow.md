# Phoenix Sync Workflow Analysis

This document provides a detailed analysis of the `phoenix sync` command, which is the core orchestration engine for the Phoenix Hypervisor platform.

## Overview

The `phoenix sync` command is a multi-stage process that configures and synchronizes the entire hypervisor environment based on a set of declarative JSON configuration files. It is designed to be idempotent, meaning it can be run multiple times safely, and it will only make changes necessary to bring the system to its desired state.

## Workflow Diagram

```mermaid
graph TD
    A[phoenix sync all] --> B{phoenix-cli};
    B --> C{portainer-manager.sh};
    C --> D[Stage 0: Sync Stack Files];
    D --> E[Stage 1: Core Infrastructure];
    E --> F[Stage 2: Docker Swarm];
    F --> G[Stage 3: Deploy Services];
    G --> H[Stage 4: Configure Gateway];
    H --> I[Stage 5: Sync Stacks (Deprecated)];

    subgraph Stage 1
        E1[Install Trusted CA]
        E2[Setup DNS Server]
        E3[Setup Firewall]
        E4[Renew Certificates]
    end

    subgraph Stage 2
        F1[Initialize Swarm]
        F2[Join Worker Nodes]
    end

    subgraph Stage 3
        G1[Deploy Portainer]
        G2[Deploy Traefik]
    end

    E --> E1 --> E2 --> E3 --> E4;
    F --> F1 --> F2;
    G --> G1 --> G2;
```

## Detailed Stage-by-Stage Breakdown

### Entry Point: `phoenix-cli`

*   **File:** `usr/local/phoenix_hypervisor/bin/phoenix-cli`
*   **Responsibility:** Acts as the main dispatcher for all `phoenix` commands. When it receives the `sync` verb, it immediately hands off execution to the `portainer-manager.sh` script.

### Orchestrator: `portainer-manager.sh`

*   **File:** `usr/local/phoenix_hypervisor/bin/managers/portainer-manager.sh`
*   **Responsibility:** This is the master script that orchestrates the entire sync process. The `sync_all` function defines the main stages of the operation.

### Stage 0: Sync Stack Files

*   **Action:** The script begins by using `rsync` to synchronize the Docker Compose files and `phoenix.json` manifests from the local Git repository to a shared ZFS dataset (`/quickOS/portainer_stacks/`).
*   **Purpose:** This ensures that the Docker Swarm manager has access to the most recent versions of all application stack definitions.

### Stage 1: Core Infrastructure Synchronization

This stage configures the foundational networking and security services.

1.  **Install Trusted CA:**
    *   **Script:** `hypervisor_feature_install_trusted_ca.sh`
    *   **Action:** Copies the root CA certificate from the Step-CA container to the Proxmox host's trust store.
    *   **Purpose:** Allows the hypervisor to trust the internal TLS certificates used by various services.

2.  **Setup DNS Server:**
    *   **Script:** `hypervisor_feature_setup_dns_server.sh`
    *   **Action:** Configures `dnsmasq` on the host. It uses a powerful `jq` query to aggregate DNS records from all LXC, VM, and stack configurations into a single, unified DNS view.
    *   **Purpose:** Provides reliable, internal-only name resolution for all services.

3.  **Setup Firewall:**
    *   **Script:** `hypervisor_feature_setup_firewall.sh`
    *   **Action:** Generates and applies a global firewall ruleset (`cluster.fw`) by aggregating rules from the main config, as well as individual LXC and VM definitions.
    *   **Purpose:** Establishes a centralized and declarative security policy for the entire cluster.

4.  **Renew Certificates:**
    *   **Script:** `certificate-renewal-manager.sh`
    *   **Action:** Reads the `certificate-manifest.json` file, checks each certificate for impending expiration, renews it via Step-CA if necessary, and runs post-renewal commands (e.g., `systemctl reload nginx`).
    *   **Purpose:** Automates the entire lifecycle of internal TLS certificates, ensuring services never have expired certificates.

### Stage 2: Docker Swarm Cluster

*   **Script:** `swarm-manager.sh` (called by `portainer-manager.sh`)
*   **Responsibility:** This script manages the Docker Swarm cluster in a declarative way, based on the `swarm_role` defined in `phoenix_vm_configs.json`.
*   **Actions:**
    *   **Initialize Swarm:** If the Swarm is not already active, it initializes it on the designated manager node.
    *   **Join Worker Nodes:** It iterates through all VMs with `swarm_role: worker`, checks if they are part of the Swarm, and joins them if they are not.
    *   **Apply Labels:** It applies any node labels defined in the configuration, which is essential for service placement.

### Stage 3: Deploy Upstream Services

*   **Action:** The `portainer-manager.sh` script deploys the core services required for the platform to function.
*   **Services:**
    *   **Portainer:** Deploys the Portainer server and agent. It also handles the initial admin user setup.
    *   **Traefik:** Deploys the Traefik reverse proxy and configures it to route traffic to the appropriate services.

### Stage 4: Configure NGINX Gateway

*   **Action:** The script generates a dynamic NGINX configuration and pushes it to the NGINX container.
*   **Purpose:** The NGINX gateway acts as the main entry point for all external traffic, routing it to the Traefik reverse proxy, which then routes it to the appropriate backend service.

### Stage 5: Synchronize Portainer Stacks (Deprecated)

*   **Action:** This stage was originally designed to use the Portainer API to deploy all the application stacks.
*   **Current Status:** The logs and script comments indicate that this stage is now deprecated in favor of a manual deployment workflow through the Portainer UI.

## Configuration-Driven by Design

The entire `phoenix sync` process is driven by a set of declarative JSON files:

*   `phoenix_hypervisor_config.json`: Global settings.
*   `phoenix_lxc_configs.json`: LXC definitions.
*   `phoenix_vm_configs.json`: VM definitions.
*   `certificate-manifest.json`: Certificate lifecycle definitions.

This declarative approach is the key to the system's robustness and reproducibility. The scripts simply read the desired state from these files and execute the necessary commands to make the system's actual state match the desired state.

## Conclusion

The `phoenix sync` command is a sophisticated and well-designed orchestration system. It automates the complex process of configuring a secure, resilient, and fully functional hypervisor environment. The declarative, configuration-driven approach and the idempotent nature of the scripts make it a powerful and reliable tool for managing the Phoenix Hypervisor platform.