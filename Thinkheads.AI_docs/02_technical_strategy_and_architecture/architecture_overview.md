# Phoenix Hypervisor Architecture Overview

This document provides a high-level overview of the core components of the Phoenix Hypervisor system, outlining their purpose and how they integrate to form a cohesive and automated infrastructure.

## Core Components

### LXC 103: Step-CA
*   **Purpose**: The trusted certificate authority for the entire internal network. It is responsible for issuing and renewing all TLS certificates for the internal services.
*   **Integration**: It is the first component to be brought online, as all other secure services depend on it for their certificates.

### LXC 101: Nginx-Phoenix
*   **Purpose**: The primary entry point for all external traffic. It acts as the sole TLS termination point for the entire internal network and proxies all traffic to the internal Traefik service mesh.
*   **Integration**: It depends on Step-CA (103) for its TLS certificate and is the gateway for all other services.

### LXC 102: Traefik-Internal
*   **Purpose**: The internal service mesh and reverse proxy. It is responsible for routing traffic to the appropriate backend service based on the hostname.
*   **Integration**: It receives all its traffic from the Nginx gateway (101) and is responsible for routing it to the appropriate LXC or VM.

### VM 1001: Portainer
*   **Purpose**: The centralized management UI for the Docker environments. It is responsible for deploying and managing all the Docker stacks.
*   **Integration**: It is the primary control plane for all the application-level services and is managed by the `portainer-manager.sh` script.

### VM 1002: drphoenix
*   **Purpose**: The primary application host. It runs the Portainer agent and is the target for all the application-level Docker stacks.
*   **Integration**: It is managed by the Portainer server (1001) and is the host for all the core applications.

## Architecture & Workflow Diagram

```mermaid
graph TD
    subgraph Proxmox Host
        A[phoenix-cli]
        B[dnsmasq]
        C[Firewall]
    end

    subgraph "VM 1001: Portainer"
        D[Portainer Server]
    end

    subgraph "VM 1002: drphoenix"
        E[Portainer Agent]
        F[Applications]
    end

    subgraph "LXC 103: Step-CA"
        G[Step-CA]
    end

    subgraph "LXC 101: Nginx-Phoenix"
        H[Nginx]
    end

    subgraph "LXC 102: Traefik-Internal"
        I[Traefik]
    end

    A -- Manages --> B
    A -- Manages --> C
    A -- Manages --> D
    A -- Manages --> E
    A -- Manages --> G
    A -- Manages --> H
    A -- Manages --> I

    H -- Proxies to --> I
    I -- Routes to --> D
    I -- Routes to --> F
    D -- Manages --> E
    E -- Manages --> F

    G -- Issues Certs to --> H
    G -- Issues Certs to --> I
    G -- Issues Certs to --> D
```

## `phoenix sync all` Workflow

The `phoenix sync all` command is the master orchestrator responsible for bringing the entire system to its desired state. It performs the following key actions in sequence:

1.  **Host-Level Synchronization**:
    *   Ensures the Proxmox host's DNS server (`dnsmasq`) is correctly configured with all guest hostnames.
    *   Applies all global and per-guest firewall rules.
    *   Runs the `certificate-renewal-manager` to ensure all TLS certificates are valid and up-to-date.

2.  **Swarm Initialization**:
    *   Initializes the Docker Swarm on the manager node (VM 1001).
    *   Ensures all designated worker nodes (e.g., VM 1002) are actively joined to the Swarm.

3.  **Portainer Deployment**:
    *   Deploys the Portainer server stack to the Swarm manager node.
    *   Sets up the initial admin user and generates an API key for future automation.

4.  **Service Mesh Configuration**:
    *   Executes `generate_traefik_config.sh` on the host to create a dynamic configuration based on all defined `traefik_service` objects in the system.
    *   Pushes the generated configuration into the Traefik container (102) and reloads the service.

5.  **Gateway Configuration (Refactored)**:
    *   Executes `generate_nginx_config.sh` on the host to create the gateway configuration.
    *   Pushes the generated configuration into the Nginx container (101).
    *   Reloads the Nginx service to apply the new configuration. This host-based generation process ensures reliability and consistency, avoiding the brittle in-container scripting of the previous implementation.

6.  **Application Stack Deployment**:
    *   Synchronizes all application stack definitions (e.g., `qdrant_service`, `thinkheads_ai_app`) to the shared volume.
    *   Deploys all stacks designated in the VM configurations to the appropriate Swarm nodes.