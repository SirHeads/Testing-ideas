---
title: 'LXC Container 955: ollamaBase - Architecture and Implementation Plan'
summary: This document outlines the architectural plan for the creation and configuration
  of LXC container `955`, designated `ollamaBase`. This container will serve as a
  standardized, GPU-accelerated base for running Ollama models. The plan ensures alignment
  with the platform's existing standards for GPU passthrough, driver installation,
  and automated setup, drawing from the established architecture of `BaseTemplateGPU`
  (CTID `901`).
document_type: Strategy | Technical | Business Case | Report
status: Draft | In Review | Approved | Archived
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Team/Individual Name
tags:
- LXC Container
- Ollama
- Architecture
- Implementation Plan
- Phoenix Hypervisor
- GPU
- AI
- Machine Learning
review_cadence: Annual | Quarterly | Monthly | None
last_reviewed: YYYY-MM-DD
---
This document outlines the architectural plan for the creation and configuration of LXC container `955`, designated `ollamaBase`. This container will serve as a standardized, GPU-accelerated base for running Ollama models. The plan ensures alignment with the platform's existing standards for GPU passthrough, driver installation, and automated setup, drawing from the established architecture of `BaseTemplateGPU` (CTID `901`).

The setup will be fully automated through a dedicated application script, `phoenix_hypervisor_lxc_955.sh`, and managed via the central `phoenix_lxc_configs.json` file.

## 1. Introduction

This document outlines the architectural plan for the creation and configuration of LXC container `955`, designated `ollamaBase`. This container will serve as a standardized, GPU-accelerated base for running Ollama models. The plan ensures alignment with the platform's existing standards for GPU passthrough, driver installation, and automated setup, drawing from the established architecture of `BaseTemplateGPU` (CTID `901`).

The setup will be fully automated through a dedicated application script, `phoenix_hypervisor_lxc_955.sh`, and managed via the central `phoenix_lxc_configs.json` file.

## 2. High-Level Plan

The deployment will follow these stages:

1.  **Configuration:** Update `phoenix_lxc_configs.json` with the parameters for container `955`, including its name, resource allocation, GPU assignment, and the designated application script.
2.  **Script Creation:** Develop the application runner script, `phoenix_hypervisor_lxc_955.sh`, to automate the installation and configuration of the Ollama service.
3.  **Execution:** The `phoenix_orchestrator.sh` script will use the updated configuration to create, configure, and launch the container, including the execution of the `nvidia` feature.
4.  **Validation:** The new script will perform health checks to ensure the Ollama service is operational and the GPU is correctly utilized.

## 3. Requirements

### 3.1. Functional Requirements

- The container must run a stable version of the Ollama service.
- The Ollama API must be accessible on the network at `http://10.0.0.155:11434`.
- The service must fully support GPU acceleration for running language models.
- The Ollama service must be managed by `systemd` to ensure it is persistent and restarts on failure.
- Model storage must be persistent, with models stored in a designated directory within the container (e.g., `/usr/share/ollama/.ollama/models`).
- The setup must be script-driven, with all installation and configuration steps automated.

### 3.2. Non-Functional Requirements

- The container setup must be fully automated and repeatable.
- All configuration parameters must be centralized in `phoenix_lxc_configs.json`.
- The container will be cloned from the `BaseTemplateGPU` (CTID `901`) to inherit the necessary GPU environment.
- Resource allocation (CPU, memory, storage) must be sufficient for running large language models.
- The container must have a dedicated GPU assignment to ensure consistent performance.

## 4. Technical Specifications

### 4.1. LXC Configuration (`phoenix_lxc_configs.json`)

The configuration for CTID `955` will be as follows, ensuring it inherits from the GPU base template and receives a dedicated GPU assignment:

```json
"955": {
    "name": "ollamaBase",
    "memory_mb": 32768,
    "cores": 8,
    "storage_pool": "quickOS-lxc-disks",
    "storage_size_gb": 128,
    "network_config": {
        "name": "eth0",
        "bridge": "vmbr0",
        "ip": "10.0.0.155/24",
        "gw": "10.0.0.1"
    },
    "mac_address": "52:54:00:67:89:B5",
    "gpu_assignment": "0",
    "unprivileged": true,
    "portainer_role": "none",
    "clone_from_ctid": "901",
    "features": [
        "nvidia"
    ],
    "application_script": "phoenix_hypervisor_lxc_955.sh"
}
```

### 4.2. Resource Allocation

-   **CPU:** 8 cores
-   **Memory:** 32768 MB
-   **Storage:** 128 GB on the `quickOS-lxc-disks` pool.
-   **GPU:** Dedicated assignment of GPU `0`.

### 4.3. Software Stack

-   **Base OS:** Ubuntu 24.04 (inherited from `BaseTemplateGPU`)
-   **NVIDIA Driver:** Version `580.76.05` (installed by the `nvidia` feature)
-   **CUDA Toolkit:** Version `12.8` (installed by the `nvidia` feature)
-   **Ollama Service:** Latest stable version, installed via the official installation script.

## 5. Scripting Needs

### 5.1. `phoenix_hypervisor_lxc_955.sh`

A new script, `phoenix_hypervisor_lxc_955.sh`, will be created in `phoenix_hypervisor/bin/`. This script will be responsible for the complete setup and configuration of the Ollama service.

**Key Responsibilities:**

-   **Ollama Installation:**
    -   Download and execute the official Ollama installation script (`curl -fsSL https://ollama.com/install.sh | sh`).
    -   The script is idempotent and will handle cases where Ollama is already installed.
-   **Service Management:**
    -   Ensure the Ollama `systemd` service is enabled to start on boot (`systemctl enable ollama`).
    -   Start and restart the Ollama service as needed.
-   **Health Check:**
    -   Perform a health check by curling the Ollama API endpoint (`http://localhost:11434`).
    -   Verify that the service is responsive and that `nvidia-smi` reports a healthy GPU status.
-   **Display Connection Info:** Output the IP address and port for user access.

### 5.2. Feature Scripts

-   **`nvidia`:** This existing feature script will be used to handle the GPU passthrough, driver installation, and CUDA toolkit setup. No modifications are required.
-   **Post-Setup Scripts (Optional):**
    -   A potential feature script could be developed to pre-load specific models into the Ollama instance (e.g., `ollama pull llama3`).
    -   Another script could manage user access or configure advanced Ollama settings, suchs as custom model paths.

## 6. Workflow Diagram

```mermaid
graph TD
    A[Start] --> B{Update phoenix_lxc_configs.json with ollamaBase config};
    B --> C{Create phoenix_hypervisor_lxc_955.sh};
    C --> D{Implement Ollama installation and service management in script};
    D --> E{Run phoenix_orchestrator.sh for CTID 955};
    E --> F{Container Cloned from 901 BaseTemplateGPU};
    F --> G{NVIDIA Feature Executed GPU Passthrough and Driver Install};
    G --> H{Application Script Executed};
    H --> I{Ollama Service Started and Configured};
    I --> J{Health Check & GPU Validation};
    J --> K[End];
