# Phoenix Hypervisor Architecture Overview

This document outlines the architecture of the Phoenix Hypervisor environment, detailing the roles and responsibilities of each major component.

### Component Identities and Purposes

*   **LXC 103 (`Step-CA`):**
    *   **Identity:** Certificate Authority Server.
    *   **Purpose:** This container runs `step-ca`, a private certificate authority. Its primary role is to issue and manage TLS certificates for all the internal services. This ensures that all communication within your network is encrypted and secure (HTTPS). It's the foundational security layer and boots first.

*   **LXC 101 (`Nginx-Phoenix`):**
    *   **Identity:** Public-Facing Web Gateway.
    *   **Purpose:** This Nginx container acts as the main entry point for traffic from outside the hypervisor. It handles incoming requests on ports 80 and 443 and forwards them to the internal Traefik proxy (LXC 102). It likely handles initial TLS termination and routing.

*   **LXC 102 (`Traefik-Internal`):**
    *   **Identity:** Internal Reverse Proxy & Service Discovery.
    *   **Purpose:** Traefik serves as the dynamic internal router. It automatically discovers services (like Docker containers) as they come online and routes traffic to them based on hostnames (e.g., `portainer.internal.thinkheads.ai`). It integrates with `step-ca` to secure the internal services with valid TLS certificates.

*   **VM 1001 (`Portainer`):**
    *   **Identity:** Container Orchestration Manager.
    *   **Purpose:** This is the control plane for your Docker environment. It runs the Portainer server, providing a web UI to manage everything. It is also configured as the **Docker Swarm manager**, responsible for coordinating the deployment and state of all Docker services.

*   **VM 1002 (`drphoenix`):**
    *   **Identity:** Docker Swarm Worker Node.
    *   **Purpose:** This VM acts as a worker node in the Docker Swarm cluster. Its job is to run the actual application containers (Docker services) as instructed by the Swarm manager (VM 1001). It runs the Portainer agent to communicate with the manager.

### Docker Services

*   **`portainer_service`:**
    *   **Purpose:** This is the Portainer application itself, running as a Docker container on the manager node (VM 1001).
*   **`qdrant_service`:**
    *   **Purpose:** This service runs a Qdrant vector database on the worker node (VM 1002). Vector databases are commonly used in AI applications for tasks like semantic search and Retrieval-Augmented Generation (RAG).

### Architectural Flow

The `phoenix sync all` command triggers the `portainer-manager.sh` script. This process connects to the Portainer API on VM 1001 and instructs it to deploy or update the Docker stacks (`portainer_service` and `qdrant_service`) on the appropriate nodes in the Swarm cluster according to the configuration.

### Architecture Diagram

```mermaid
graph TD
    subgraph Hypervisor
        subgraph "LXC Containers"
            LXC103["103: Step-CA<br>(Certificate Authority)"]
            LXC101["101: Nginx-Phoenix<br>(Web Gateway)"]
            LXC102["102: Traefik-Internal<br>(Internal Proxy)"]
        end
        subgraph "Virtual Machines"
            VM1001["1001: Portainer<br>(Swarm Manager)"]
            VM1002["1002: drphoenix<br>(Swarm Worker)"]
        end
    end

    subgraph "Docker Services"
        PortainerService["portainer_service"]
        QdrantService["qdrant_service"]
    end

    Internet -->|HTTPS: 443| LXC101
    LXC101 -->|Forwards Traffic| LXC102
    LXC102 -->|Routes to| VM1001
    LXC102 -->|Routes to| QdrantService

    VM1001 -- Manages --> VM1002
    VM1001 -- Deploys --> PortainerService
    VM1002 -- Runs --> QdrantService

    LXC101 -- Needs Certs --> LXC103
    LXC102 -- Needs Certs --> LXC103
    VM1001 -- Needs Certs --> LXC103
    VM1002 -- Needs Certs --> LXC103

    classDef lxc fill:#cce5ff,stroke:#333,stroke-width:2px;
    classDef vm fill:#d5e8d4,stroke:#333,stroke-width:2px;
    classDef service fill:#f8cecc,stroke:#333,stroke-width:2px;

    class LXC101,LXC102,LXC103 lxc;
    class VM1001,VM1002 vm;
    class PortainerService,QdrantService service;