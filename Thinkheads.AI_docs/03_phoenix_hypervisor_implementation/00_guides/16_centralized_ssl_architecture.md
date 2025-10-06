# Centralized SSL Certificate Architecture

## Overview

This document outlines the centralized SSL certificate management architecture for the Phoenix Hypervisor environment. The primary goal of this architecture is to create a single source of truth for self-signed SSL certificates, ensuring that all services that require them (such as the Nginx gateway and the Portainer server) are using the same, valid certificates.

## Architecture and Workflow

The architecture is managed through a series of scripts that are orchestrated by the main `phoenix-cli` dispatcher.

```mermaid
graph TD
    A[phoenix create] --> B{generate_ssl_certs.sh};
    B --> C[lxc-manager.sh];
    B --> D[vm-manager.sh];
    C --> E[LXC 101: Nginx Gateway];
    D --> F[VM 1001: Portainer Server];
    G[/usr/local/phoenix_hypervisor/persistent-storage/ssl] --> E;
    G --> F;

    subgraph Hypervisor
        A;
        B;
        C;
        D;
        G;
    end

    subgraph Guests
        E;
        F;
    end
```

### Workflow Steps:

1.  **Initiation**: The process begins when a user runs a `phoenix create` or `phoenix converge` command.

2.  **Certificate Generation**: Before any guest creation begins, the `phoenix-cli` script calls the `generate_ssl_certs.sh` script.
    *   **Idempotency**: This script is idempotent. It checks for the existence of certificates in the central store (`/usr/local/phoenix_hypervisor/persistent-storage/ssl`). If the certificates already exist, the script does nothing. If they are missing, it generates them.
    *   **Central Store**: This ensures that a single, consistent set of certificates is always available on the hypervisor.

3.  **Guest Provisioning**: The `phoenix-cli` proceeds to call the appropriate manager (`lxc-manager.sh` or `vm-manager.sh`) to provision the requested guests.

4.  **Nginx Gateway (LXC 101)**:
    *   When `lxc-manager.sh` provisions the Nginx gateway, the `apply_mount_points` function mounts the central SSL store from the hypervisor directly into the container at `/etc/nginx/ssl`.
    *   The `phoenix_hypervisor_lxc_101.sh` script, which runs inside the container, no longer needs to generate its own certificates; it simply uses the ones provided in the mounted directory.

5.  **Portainer Server (VM 1001)**:
    *   When `vm-manager.sh` provisions the Portainer server, the `apply_vm_features` function copies the certificates from the central SSL store on the hypervisor into the Portainer VM's persistent storage directory (`.../portainer/ssl`).
    *   The `docker-compose.yml` file for Portainer mounts this directory into the container, allowing the Portainer service to use the correct, centralized certificates.

## Benefits of this Architecture

*   **Single Source of Truth**: Eliminates certificate mismatches and ensures all services trust each other.
*   **Idempotent and Resilient**: The process can be run safely multiple times. Certificates are only generated when needed, making the creation process robust.
*   **Simplified Management**: Centralizes the creation and storage of certificates, making them easier to manage, update, or replace in the future.