---
title: 'LXC Container 956: openWebUIBase - Architecture and Implementation Plan'
summary: This document outlines the architectural plan for the creation and configuration of LXC container 956.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- LXC Container
- Open WebUI
- Ollama
- Architecture
- Implementation Plan
- Web Interface
review_cadence: Annual
last_reviewed: 2025-09-23
---
This document outlines the architectural plan for the creation and configuration of LXC container `956`, designated `openWebUIBase`. This container will provide a web-based user interface for interacting with the Ollama API, which is hosted in the `ollamaBase` container (CTID `955`).

The plan ensures that the container is configured for seamless network communication with the Ollama container, provides persistent storage for user data and configurations, and is deployed in a fully automated and repeatable manner. The setup will be managed through the central `phoenix_lxc_configs.json` file and automated by a dedicated application script, `phoenix_hypervisor_lxc_956.sh`.

## 1. Introduction

This document outlines the architectural plan for the creation and configuration of LXC container `956`, designated `openWebUIBase`. This container will provide a web-based user interface for interacting with the Ollama API, which is hosted in the `ollamaBase` container (CTID `955`).

The plan ensures that the container is configured for seamless network communication with the Ollama container, provides persistent storage for user data and configurations, and is deployed in a fully automated and repeatable manner. The setup will be managed through the central `phoenix_lxc_configs.json` file and automated by a dedicated application script, `phoenix_hypervisor_lxc_956.sh`.

## 2. High-Level Plan

The deployment will follow these stages:

1.  **Configuration:** Update `phoenix_lxc_configs.json` with the parameters for container `956`, including its name, resource allocation, and the designated application script.
2.  **Script Creation:** Develop the application runner script, `phoenix_hypervisor_lxc_956.sh`, to automate the installation and configuration of the Open WebUI.
3.  **Execution:** The `phoenix_orchestrator.sh` script will use the updated configuration to create, configure, and launch the container.
4.  **Validation:** The new script will perform health checks to ensure the Open WebUI is accessible and can communicate with the Ollama API.

## 3. Requirements

### 3.1. Functional Requirements

- The container must run a stable version of the Open WebUI.
- The web interface must be accessible on the network at `http://10.0.0.156:8080`.
- The Open WebUI must be able to connect to the Ollama API at `http://10.0.0.155:11434`.
- User data, conversations, and settings must be stored in a persistent volume.
- The setup must be script-driven, with all installation and configuration steps automated.

### 3.2. Non-Functional Requirements

- The container setup must be fully automated and repeatable.
- All configuration parameters must be centralized in `phoenix_lxc_configs.json`.
- The container will be cloned from the `BaseTemplate` (CTID `900`) as it does not require GPU passthrough.
- Resource allocation (CPU, memory, storage) must be sufficient for a responsive web interface.
- The container must have a static IP address to ensure reliable communication with the Ollama container.

## 4. Technical Specifications

### 4.1. LXC Configuration (`phoenix_lxc_configs.json`)

The configuration for CTID `956` will be as follows:

```json
"956": {
    "name": "openWebUIBase",
    "memory_mb": 4096,
    "cores": 2,
    "storage_pool": "quickOS-lxc-disks",
    "storage_size_gb": 32,
    "network_config": {
        "name": "eth0",
        "bridge": "vmbr0",
        "ip": "10.0.0.156/24",
        "gw": "10.0.0.1"
    },
    "mac_address": "52:54:00:67:89:B6",
    "unprivileged": true,
    "portainer_role": "none",
    "clone_from_ctid": "900",
    "features": [
        "docker"
    ],
    "application_script": "phoenix_hypervisor_lxc_956.sh"
}
```

### 4.2. Resource Allocation

-   **CPU:** 2 cores
-   **Memory:** 4096 MB
-   **Storage:** 32 GB on the `quickOS-lxc-disks` pool.

### 4.3. Software Stack

-   **Base OS:** Ubuntu 24.04 (inherited from `BaseTemplate`)
-   **Docker:** Latest stable version (installed by the `docker` feature).
-   **Open WebUI:** Latest stable version, deployed as a Docker container.

## 5. Scripting Needs

### 5.1. `phoenix_hypervisor_lxc_956.sh`

A new script, `phoenix_hypervisor_lxc_956.sh`, will be created in `phoenix_hypervisor/bin/`. This script will be responsible for the complete setup and configuration of the Open WebUI.

**Key Responsibilities:**

-   **Open WebUI Installation:**
    -   Pull the official Open WebUI Docker image.
    -   Create a persistent volume for Open WebUI data.
    -   Start the Open WebUI container, mapping port `8080` and mounting the data volume.
-   **Service Management:**
    -   Ensure the Docker container is configured to restart automatically.
-   **Health Check:**
    -   Perform a health check by curling the Open WebUI endpoint (`http://localhost:8080`).
    -   Verify that the web interface is responsive.
-   **Display Connection Info:** Output the IP address and port for user access.

### 5.2. Feature Scripts

-   **`docker`:** This existing feature script will be used to handle the Docker installation. No modifications are required.
-   **Post-Setup Scripts (Optional):**
    -   A potential feature script could be developed to pre-configure the Open WebUI to connect to the `ollamaBase` container.
    -   Another script could manage user authentication or set up a reverse proxy for the web interface.

## 6. Workflow Diagram

```mermaid
graph TD
    A[Start] --> B{Update phoenix_lxc_configs.json with openWebUIBase config};
    B --> C{Create phoenix_hypervisor_lxc_956.sh};
    C --> D{Implement Open WebUI installation in script};
    D --> E{Run phoenix_orchestrator.sh for CTID 956};
    E --> F{Container Cloned from 900 BaseTemplate};
    F --> G{Docker Feature Executed};
    G --> H{Application Script Executed};
    H --> I{Open WebUI Container Started};
    I --> J{Health Check};
    J --> K[End];
