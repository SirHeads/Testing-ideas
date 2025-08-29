# LXC Container 910 - Portainer - Requirements & Details

## Overview

This document details the purpose, configuration, and setup process for LXC container `910`, named `Portainer`. This container serves as the central management hub for the Docker environments within the Phoenix Hypervisor system. It runs the Portainer Server, providing a web-based UI to manage Docker containers running on the Proxmox host and other Portainer Agents. Unlike the base templates, this is a final, functional application container.

## Core Purpose & Function

*   **Role:** Portainer Server.
*   **Primary Function:** Host the Portainer web application, allowing centralized management of Docker environments across the system. This includes managing containers, images, networks, and volumes on the Proxmox host and in other LXC containers running the Portainer Agent.
*   **Usage:** This is a permanent, running service container. It is created by cloning from an existing Docker-enabled template snapshot.

## Configuration (`phoenix_lxc_configs.json`)

*   **CTID:** `910`
*   **Name:** `Portainer`
*   **Template Source:** `/fastData/shared-iso/template/cache/ubuntu-24.04-standard_24.04-2_amd64.tar.zst` (Note: While the template path is specified, this container is created by cloning).
*   **Resources:**
    *   **CPU Cores:** `6` (Allocated cores for the Portainer Server process)
    *   **Memory:** `32768` MB (32 GB RAM, allocated for the Portainer Server process)
    *   **Storage Pool:** `lxc-disks`
    *   **Storage Size:** `128` GB (Root filesystem size)
*   **Network Configuration:**
    *   **Interface:** `eth0`
    *   **Bridge:** `vmbr0`
    *   **IP Address:** `10.0.0.99/24` (Permanent IP address for accessing the Portainer web UI)
    *   **Gateway:** `10.0.0.1`
    *   **MAC Address:** `52:54:00:67:89:99`
*   **LXC Features:** `nesting=1` (Essential feature to enable Docker-in-LXC, necessary for running the Portainer Docker container)
*   **Security & Privileges:**
    *   **Unprivileged:** `true` (Runs in unprivileged mode for enhanced security)
*   **GPU Assignment:** `none` (Portainer Server itself does not require GPU access)
*   **Portainer Role:** `server` (Identifies this container's role within the Portainer management system)
*   **Cloning Metadata:**
    *   **`clone_from_template_ctid`:** `902` (Indicates this container is created by cloning from container `902`'s `docker-snapshot`)

## Specific Setup Script (`phoenix_hypervisor_setup_910.sh`) Requirements

The `phoenix_hypervisor_setup_910.sh` script is responsible for the final configuration of the `Portainer` container *after* it has been cloned from `902`'s `docker-snapshot` and booted. Its core responsibilities are:

1.  **Portainer Server Deployment:**
    *   Ensure the container is fully booted and Docker is running (inherited from the `902` template).
    *   Pull the official Portainer Server Docker image (e.g., `portainer/portainer-ce:<version>`).
    *   Run the Portainer Server Docker container with the correct configuration:
        *   Map the necessary ports (e.g., `-p 9443:9443` for the web UI).
        *   Mount the Docker socket (`-v /var/run/docker.sock:/var/run/docker.sock`) to allow Portainer to manage the host's Docker instance.
        *   Mount a volume for persistent Portainer data (`-v portainer_data:/data`).
        *   Set the container name (e.g., `--name portainer`).
        *   Configure restart policies (e.g., `--restart=always`).

2.  **Initial Configuration & Verification:**
    *   Wait briefly to allow the Portainer service to initialize.
    *   Perform checks to ensure the Portainer container is running (`docker ps`).
    *   (Optional/Advanced) If possible, automate initial setup steps like setting the admin password via the Portainer API (though this often requires the service to be initially accessed via UI).
    *   Log a message indicating the Portainer Server should now be accessible at `https://10.0.0.99:9443`.

3.  **Final State:**
    *   The script ensures the Portainer service is up and running.
    *   It does *not* create a ZFS snapshot for templating, as this is a final application container.

## Interaction with Phoenix Hypervisor System

*   **Creation:** `phoenix_establish_hypervisor.sh` will identify `910` as a standard container (not `is_template: true`) and see that `clone_from_template_ctid: "902"`. It will therefore call the cloning process (`phoenix_hypervisor_clone_lxc.sh`) to create `910` by cloning `902`'s `docker-snapshot`.
*   **Setup:** After cloning and initial boot, `phoenix_establish_hypervisor.sh` will execute `phoenix_hypervisor_setup_910.sh`.
*   **Consumption:** Other containers configured as Portainer Agents (`portainer_role: "agent"`) will connect to this server using its IP (`10.0.0.99`) and the configured agent port (`9001` as defined in `phoenix_hypervisor_config.json`).
*   **Idempotency:** The setup script (`phoenix_hypervisor_setup_910.sh`) should be idempotent. If the Portainer container is already running, it should skip the deployment steps and just log that the service is already configured.

## Key Characteristics Summary

*   **Application Container:** A final, functional service, not a template.
*   **Management Hub:** Runs the Portainer Server web UI for Docker management.
*   **Docker-in-LXC:** Relies on the `nesting=1` feature inherited from its base template (`902`).
*   **Secure:** Runs unprivileged (`unprivileged: true`).
*   **Static Network:** Uses a fixed IP (`10.0.0.99`) for reliable access.
*   **No GPU:** Does not require GPU access.
*   **Cloned Origin:** Created by cloning the `docker-snapshot` from `BaseTemplateDocker` (`902`).