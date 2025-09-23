---
title: 'LXC Container 957: llamacppBase - Architecture and Implementation Plan'
summary: This document outlines the architectural plan for the creation and configuration of LXC container 957.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- LXC Container
- llama.cpp
- GPU
- Architecture
- Implementation Plan
- AI
- Machine Learning
review_cadence: Annual
last_reviewed: 2025-09-23
---
This document outlines the architectural plan for the creation and configuration of LXC container `957`, designated `llamacppBase`. This container will serve as a standardized, GPU-accelerated base for compiling and running models with `llama.cpp`. The plan ensures alignment with the platform's existing standards for GPU passthrough, driver installation, and automated setup, drawing from the established architecture of `BaseTemplateGPU` (CTID `901`) and `ollamaBase` (CTID `955`).

The setup will be fully automated through a dedicated application script, `phoenix_hypervisor_lxc_957.sh`, and managed via the central `phoenix_lxc_configs.json` file.

## 1. Introduction

This document outlines the architectural plan for the creation and configuration of LXC container `957`, designated `llamacppBase`. This container will serve as a standardized, GPU-accelerated base for compiling and running models with `llama.cpp`. The plan ensures alignment with the platform's existing standards for GPU passthrough, driver installation, and automated setup, drawing from the established architecture of `BaseTemplateGPU` (CTID `901`) and `ollamaBase` (CTID `955`).

The setup will be fully automated through a dedicated application script, `phoenix_hypervisor_lxc_957.sh`, and managed via the central `phoenix_lxc_configs.json` file.

## 2. High-Level Plan

The deployment will follow these stages:

1.  **Configuration:** Update `phoenix_lxc_configs.json` with the parameters for container `957`, including its name, resource allocation, GPU assignment, and the designated application script.
2.  **Script Creation:** Develop the application runner script, `phoenix_hypervisor_lxc_957.sh`, to automate the cloning of the `llama.cpp` repository and its compilation with GPU support.
3.  **Execution:** The `phoenix_orchestrator.sh` script will use the updated configuration to create, configure, and launch the container, including the execution of the `nvidia` feature.
4.  **Validation:** The new script will perform health checks to ensure the `llama.cpp` binaries are executable and the GPU is correctly utilized.

## 3. Requirements

### 3.1. Functional Requirements

- The container must provide a complete build environment for `llama.cpp`.
- The compiled `llama.cpp` binaries must support GPU acceleration (cuBLAS).
- If a `llama.cpp` server is run, it must be accessible on the network at `http://10.0.0.157:8080`.
- Storage for models and binaries must be persistent.
- The entire setup process must be automated.

### 3.2. Non-Functional Requirements

- The container setup must be fully automated and repeatable.
- All configuration parameters must be centralized in `phoenix_lxc_configs.json`.
- The container will be cloned from the `BaseTemplateGPU` (CTID `901`).
- Resource allocation must be sufficient for compiling and running `llama.cpp` with large models.
- The container must have a dedicated GPU assignment.

## 4. Technical Specifications

### 4.1. LXC Configuration (`phoenix_lxc_configs.json`)

The configuration for CTID `957` will be as follows:

```json
"957": {
    "name": "llamacppBase",
    "memory_mb": 32768,
    "cores": 8,
    "storage_pool": "quickOS-lxc-disks",
    "storage_size_gb": 128,
    "network_config": {
        "name": "eth0",
        "bridge": "vmbr0",
        "ip": "10.0.0.157/24",
        "gw": "10.0.0.1"
    },
    "mac_address": "52:54:00:67:89:B7",
    "gpu_assignment": "1",
    "unprivileged": true,
    "portainer_role": "none",
    "clone_from_ctid": "901",
    "features": [
        "nvidia"
    ],
    "application_script": "phoenix_hypervisor_lxc_957.sh"
}
```

### 4.2. Resource Allocation

-   **CPU:** 8 cores
-   **Memory:** 32768 MB
-   **Storage:** 128 GB on the `quickOS-lxc-disks` pool.
-   **GPU:** Dedicated assignment of GPU `1`.

### 4.3. Software Stack

-   **Base OS:** Ubuntu 24.04 (inherited from `BaseTemplateGPU`)
-   **Required Packages:** `build-essential`, `cmake`, `git`
-   **NVIDIA Driver:** Version `580.76.05` (installed by the `nvidia` feature)
-   **CUDA Toolkit:** Version `12.8` (installed by the `nvidia` feature)
-   **llama.cpp:** Latest version from the official GitHub repository.

## 5. Scripting Needs

### 5.1. `phoenix_hypervisor_lxc_957.sh`

A new script, `phoenix_hypervisor_lxc_957.sh`, will be created in `phoenix_hypervisor/bin/`. This script will be responsible for the complete setup of the `llama.cpp` environment.

**Key Responsibilities:**

-   **Dependency Installation:** Install `build-essential`, `cmake`, and `git`.
-   **Repository Cloning:** Clone the `llama.cpp` repository from GitHub into a designated directory (e.g., `/opt/llama.cpp`).
-   **Compilation:**
    -   Compile `llama.cpp` with cuBLAS support by running `make` with the appropriate flags.
-   **Health Check:**
    -   Verify that the `main` and `server` binaries have been created.
    -   Run `nvidia-smi` to confirm the GPU is healthy.
-   **Display Connection Info:** Output the IP address for user access.

### 5.2. Feature Scripts

-   **`nvidia`:** This existing feature script will be used to handle the GPU passthrough, driver installation, and CUDA toolkit setup.
-   **Post-Setup Scripts (Optional):**
    -   A potential feature script could be developed to download specific GGUF models.
    -   Another script could start the `llama.cpp` server with a pre-defined model and parameters.

## 6. Workflow Diagram

```mermaid
graph TD
    A[Start] --> B{Update phoenix_lxc_configs.json with llamacppBase config};
    B --> C{Create phoenix_hypervisor_lxc_957.sh};
    C --> D{Implement llama.cpp cloning and compilation in script};
    D --> E{Run phoenix_orchestrator.sh for CTID 957};
    E --> F{Container Cloned from 901 BaseTemplateGPU};
    F --> G{NVIDIA Feature Executed GPU Passthrough and Driver Install};
    G --> H{Application Script Executed};
    H --> I{llama.cpp Compiled with GPU Support};
    I --> J{Health Check & GPU Validation};
    J --> K[End];
