---
title: 'LXC Container 953: api-gateway-lxc - Architecture and Implementation Plan'
summary: This document outlines the architectural plan for the creation and configuration of LXC container 953.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- LXC Container
- API Gateway
- Nginx
- Reverse Proxy
- Architecture
- Implementation Plan
review_cadence: Annual
last_reviewed: 2025-09-23
---
This document outlines the architectural plan for the creation and configuration of LXC container `953`, which is being re-scoped and renamed to `api-gateway-lxc`. This container will function as a high-performance, CPU-only reverse proxy and API gateway. It will serve as the central, secure entry point for all backend services, such as the vLLM containers, aligning with a scalable and manageable microservice architecture.

The setup will be fully automated through a dedicated application script and managed via the central `phoenix_lxc_configs.json` file, ensuring consistency with the platform's standards.

## 1. Introduction

This document outlines the architectural plan for the creation and configuration of LXC container `953`, which is being re-scoped and renamed to `api-gateway-lxc`. This container will function as a high-performance, CPU-only reverse proxy and API gateway. It will serve as the central, secure entry point for all backend services, such as the vLLM containers, aligning with a scalable and manageable microservice architecture.

The setup will be fully automated through a dedicated application script and managed via the central `phoenix_lxc_configs.json` file, ensuring consistency with the platform's standards.

## 2. High-Level Plan

The deployment will follow these stages:

1.  **Configuration:** Update `phoenix_lxc_configs.json` with the revised parameters for container `953`, including its new name, CPU-only resource allocation, and the designated application script.
2.  **Script Creation:** Develop a new application runner script, `phoenix_hypervisor_lxc_953.sh`, to automate the installation and configuration of a standard Nginx server.
3.  **Execution:** The `phoenix_orchestrator.sh` script will use the updated configuration to create, configure, and launch the container.
4.  **Validation:** The new script will perform health checks to ensure the Nginx service is operational and correctly configured.

## 3. Requirements

### 3.1. Functional Requirements

- The container must run a stable, high-performance Nginx web server.
- The Nginx service must be accessible on the network at `http://10.0.0.153`.
- The gateway must be configured to route requests to backend services (e.g., `vllm-granite-embed` at `10.0.0.151:8000`).
- The service must be managed by `systemd` to ensure it is persistent and restarts on failure.
- The setup must be script-driven, with Nginx configuration files managed directly by the application script.

### 3.2. Non-Functional Requirements

- The container setup must be fully automated and repeatable.
- All configuration parameters must be centralized in `phoenix_lxc_configs.json`.
- The container will be cloned from the `BaseTemplate` (CTID `900`) as it does not require any pre-installed GPU components.
- Resource allocation (CPU, memory, storage) must be appropriate for a high-traffic reverse proxy.
- The container will not have a GPU assignment.

## 4. Technical Specifications

### 4.1. LXC Configuration (`phoenix_lxc_configs.json`)

The configuration for CTID `953` will be updated as follows:

```json
"953": {
    "name": "api-gateway-lxc",
    "memory_mb": 4096,
    "cores": 4,
    "storage_pool": "quickOS-lxc-disks",
    "storage_size_gb": 32,
    "network_config": {
        "name": "eth0",
        "bridge": "vmbr0",
        "ip": "10.0.0.153/24",
        "gw": "10.0.0.1"
    },
    "mac_address": "52:54:00:67:89:B3",
    "gpu_assignment": "none",
    "unprivileged": true,
    "portainer_role": "infrastructure",
    "clone_from_ctid": "900",
    "features": [
        "base_setup"
    ],
    "application_script": "phoenix_hypervisor_lxc_953.sh"
}
```

### 4.2. Resource Allocation

-   **CPU:** 4 cores
-   **Memory:** 4096 MB
-   **Storage:** 32 GB on the `quickOS-lxc-disks` pool.
-   **GPU:** None.

## 5. Scripting Needs

### 5.1. `phoenix_hypervisor_lxc_953.sh`

A new script, `phoenix_hypervisor_lxc_953.sh`, will be created in `phoenix_hypervisor/bin/`. This script will be responsible for the complete setup and configuration of the Nginx service.

**Key Responsibilities:**

-   **Nginx Installation:** Install the latest stable version of Nginx from the standard repositories.
-   **Configuration Management:**
    -   Create a default server block configuration in `/etc/nginx/sites-available/`.
    -   This configuration will include a reverse proxy directive (`proxy_pass`) to route traffic to a backend service (e.g., `http://10.0.0.151:8000`).
    -   Enable the site by creating a symbolic link in `/etc/nginx/sites-enabled/`.
-   **Service Management:**
    -   Ensure the Nginx service is enabled to start on boot (`systemctl enable nginx`).
    -   Start and restart the Nginx service as needed during configuration.
-   **Health Check:** Perform a health check by using `curl` to check the status of the Nginx default page and the proxied service endpoint to verify the service is running and routing correctly.
-   **Display Connection Info:** Output the IP address and port for user access.

### 5.2. Feature Scripts

No new "feature" scripts are required. The `base_setup` feature is sufficient for this container.

## 6. Workflow Diagram

```mermaid
graph TD
    A[Start] --> B{Update phoenix_lxc_configs.json with api-gateway-lxc config};
    B --> C{Create phoenix_hypervisor_lxc_953.sh};
    C --> D{Implement Nginx installation and reverse proxy setup in script};
    D --> E{Run phoenix_orchestrator.sh for CTID 953};
    E --> F{Container Cloned from 900};
    F --> G{Base Setup Feature Installed};
    G --> H{Application Script Executed};
    H --> I{Nginx Service Started and Configured};
    I --> J{Health Check & Reverse Proxy Validation};
    J --> K[End];
