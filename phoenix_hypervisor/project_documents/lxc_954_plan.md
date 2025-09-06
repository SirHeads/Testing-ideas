---
title: "LXC Container 954: n8n-lxc - Architecture and Implementation Plan"
tags: ["LXC Container", "n8n", "Workflow Automation", "Architecture", "Implementation Plan", "Phoenix Hypervisor"]
summary: "This document outlines the architectural plan for the creation and configuration of LXC container `954`, named `n8n-lxc`. This container will host an n8n workflow automation instance, providing a robust and scalable environment for automating tasks and integrating various services."
version: "1.0.0"
author: "Phoenix Hypervisor Team"
---

This document outlines the architectural plan for the creation and configuration of LXC container `954`, named `n8n-lxc`. This container will host an n8n workflow automation instance, providing a robust and scalable environment for automating tasks and integrating various services. The setup will adhere to the established platform standards, ensuring consistency with previous container deployments.

## 1. Introduction

This document outlines the architectural plan for the creation and configuration of LXC container `954`, named `n8n-lxc`. This container will host an n8n workflow automation instance, providing a robust and scalable environment for automating tasks and integrating various services. The setup will adhere to the established platform standards, ensuring consistency with previous container deployments.

## 2. High-Level Plan

The deployment will follow these stages:

1.  **Configuration:** Update `phoenix_lxc_configs.json` with the specific parameters for container `954`.
2.  **Script Creation:** Develop a new application runner script, `phoenix_hypervisor_lxc_954.sh`, to automate the installation, configuration, and service management of n8n.
3.  **Execution:** The `phoenix_orchestrator.sh` script will use the updated configuration to create, configure, and launch the container.
4.  **Validation:** The new script will perform health checks to ensure the n8n service is operational and accessible.

## 3. Requirements

### 3.1. Functional Requirements

- The container must run a stable version of the n8n workflow automation tool.
- The n8n service must be accessible on the network at `http://10.0.0.154:5678`.
- The service must be managed by `systemd` to ensure it is persistent and restarts on failure.
- n8n data, including workflows and credentials, must be stored in a designated directory, `/opt/n8n/data`, to ensure data persistence.
- The setup must support user authentication to secure access to the n8n instance.

### 3.2. Non-Functional Requirements

- The container setup must be fully automated and repeatable.
- All configuration parameters must be centralized in `phoenix_lxc_configs.json`.
- The container should be based on a suitable template (e.g., a base Debian/Ubuntu template, `900`).
- Resource allocation (CPU, memory, storage) must be appropriate for handling complex and concurrent workflows.

## 4. Technical Specifications

### 4.1. LXC Configuration (`phoenix_lxc_configs.json`)

The following parameters will be added to the configuration for CTID `954`:

```json
"954": {
    "name": "n8n-lxc",
    "memory_mb": 8192,
    "cores": 4,
    "storage_pool": "lxc-disks",
    "storage_size_gb": 64,
    "network_config": {
        "name": "eth0",
        "bridge": "vmbr0",
        "ip": "10.0.0.154/24",
        "gw": "10.0.0.1"
    },
    "mac_address": "52:54:00:67:89:B4",
    "unprivileged": true,
    "portainer_role": "application",
    "clone_from_ctid": "900",
    "features": [
        "docker"
    ],
    "application_script": "phoenix_hypervisor_lxc_954.sh",
    "n8n_version": "latest"
}
```

### 4.2. Resource Allocation

-   **CPU:** 4 cores
-   **Memory:** 8192 MB
-   **Storage:** 64 GB on the `lxc-disks` pool.

### 4.3. Software and Configuration

-   **n8n:** The latest version will be installed via Docker.
-   **Docker:** The container will have Docker installed as a feature.
-   **Data Persistence:** n8n's data will be mapped to `/opt/n8n/data` on the host to ensure data persistence across container restarts.

### 4.4. Rationale for Using Docker

Running n8n within a Docker container inside the LXC provides several advantages over a direct installation:

-   **Encapsulation and Portability:** Docker encapsulates the n8n application and its dependencies, ensuring a consistent environment across different setups and simplifying future migrations.
-   **Simplified Dependency Management:** The official n8n Docker image includes all necessary dependencies, such as the correct Node.js version, eliminating the need for manual installation and potential version conflicts.
-   **Scalability and Upgrades:** Docker simplifies the process of upgrading to new n8n versions and allows for easier scaling of the service in the future.
-   **Consistency with Existing Architecture:** The use of Docker aligns with the established architecture for other services like Qdrant, promoting a consistent and manageable platform.

## 5. Scripting Needs

### 5.1. `phoenix_hypervisor_lxc_954.sh`

A new script, `phoenix_hypervisor_lxc_954.sh`, will be created in `phoenix_hypervisor/bin/`. This script will be responsible for the complete setup and configuration of the n8n service within the container.

**Key Responsibilities:**

-   **Directory Creation:** Create the `/opt/n8n/data` directory for persistent data storage.
-   **Docker Compose Setup:**
    -   Generate a `docker-compose.yml` file in `/opt/n8n/`.
    -   This file will define the n8n service, specifying the official Docker image, version, port mappings, and volume mounts.
-   **Service Management:**
    -   Use `docker-compose` to pull the n8n image and start the service.
    -   Create a `systemd` service file (`/etc/systemd/system/n8n.service`) to manage the `docker-compose` service, ensuring it starts on boot and restarts on failure.
-   **Health Check:** Perform a health check by querying the n8n API to verify the service is running correctly.
-   **Display Connection Info:** Output the IP address and port for user access.

### 5.2. Feature Scripts

-   **`n8n-reverse-proxy.sh` (Optional):** A potential feature script could be developed to configure a reverse proxy (e.g., using Nginx) to provide a more user-friendly access URL and handle SSL termination.
-   **`n8n-user-management.sh` (Optional):** Another useful script could provide an interface for managing n8n users and credentials from the command line.

## 6. Workflow Diagram

```mermaid
graph TD
    A[Start] --> B{Update phoenix_lxc_configs.json with n8n config};
    B --> C{Create phoenix_hypervisor_lxc_954.sh};
    C --> D{Implement Docker Compose and systemd setup in script};
    D --> E{Run phoenix_orchestrator.sh for CTID 954};
    E --> F{Container Cloned from 900};
    F --> G{Docker Feature Installed};
    G --> H{Application Script Executed};
    H --> I{n8n Service Started via Docker Compose};
    I --> J{Health Check & API Validation};
    J --> K[End];