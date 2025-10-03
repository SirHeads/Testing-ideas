# Portainer Deployment Architecture

This document outlines the target architecture for deploying Portainer within the Phoenix Hypervisor environment.

## Architecture Diagram

The following diagram illustrates the key components and data flows for the Portainer service.

```mermaid
graph TD
    subgraph "User"
        A[Admin User]
    end

    subgraph "Phoenix Hypervisor (Proxmox Host)"
        B[LXC 101 - Nginx Gateway]
        C[VM 1001 - Docker Host]
        D[ZFS Storage Pool]
    end

    subgraph "VM 1001"
        C1[Docker]
        C2[Portainer Container]
    end

    subgraph "ZFS Storage Pool"
        D1[portainer_data Volume]
    end

    A -- Accesses via Browser --> B
    B -- Forwards Traffic --> C2
    C1 -- Runs --> C2
    C2 -- Persists Data --> D1
```

## Key Components

*   **Admin User:** The end-user who will access and manage Docker environments through the Portainer UI.
*   **LXC 101 - Nginx Gateway:** The existing Nginx gateway, which will be configured to securely expose the Portainer service.
*   **VM 1001 - Docker Host:** The primary Docker host VM where the Portainer container will be deployed.
*   **Portainer Container:** The Portainer service, running as a Docker container within VM 1001.
*   **ZFS Storage Pool:** The underlying ZFS storage on the hypervisor, which will provide a dedicated, persistent volume for Portainer's data.

This architecture ensures that Portainer is deployed in a way that is consistent with the existing infrastructure, with clear separation of concerns and robust data persistence.