---
title: "LXC Container Implementation Guide"
summary: "A comprehensive, RAG-optimized master document detailing all LXC Container Implementations within the Phoenix Hypervisor project."
document_type: "Implementation Guide"
status: "Approved"
version: "2.0.0"
author: "Phoenix Hypervisor Team"
owner: "Developer"
tags:
  - "LXC"
  - "Containers"
  - "Phoenix Hypervisor"
  - "vLLM"
  - "Qdrant"
  - "Nginx"
  - "Ollama"
  - "n8n"
review_cadence: "Annual"
last_reviewed: "2025-09-29"
---

# LXC Container Implementation Guide

## 1. Overview

This document provides a single, authoritative, and RAG-optimized overview of all LXC Container Implementations within the Phoenix Hypervisor project. It synthesizes information from numerous planning and implementation documents, cross-referenced with the `phoenix_lxc_configs.json` file to establish a ground truth for each container's configuration and purpose.

## 2. System Architecture

The LXC containers operate within a unified network bridge (`vmbr0`) and are fronted by a central NGINX API Gateway (CTID 101). This architecture simplifies service discovery, centralizes access control, and provides a consistent interface for all backend services.

### High-Level Interaction Diagram

```mermaid
graph TD
    subgraph "External Access"
        User[User/Client]
    end

    subgraph "Network Infrastructure"
        API_Gateway[LXC 101: NGINX API Gateway]
    end

    subgraph "Core AI/ML Services"
        VLLM_Chat[LXC 950: vLLM Chat Service]
        VLLM_Embed[LXC 801: vLLM Embedding Service]
        Qdrant[LXC 952: Qdrant Vector DB]
        Ollama[LXC 955: Ollama Service]
        LlamaCPP[LXC 957: Llama.cpp Service]
    end

    subgraph "Supporting Services"
        DockerVM["VM 8001: Docker Services"]
    end

    User -- HTTPS --> API_Gateway
    API_Gateway -- Routes to --> VLLM_Chat
    API_Gateway -- Routes to --> VLLM_Embed
    API_Gateway -- Routes to --> Qdrant
    API_Gateway -- Routes to --> Ollama
    API_Gateway -- Routes to --> LlamaCPP
    API_Gateway -- Routes to --> DockerVM

    DockerVM -- Hosts --> N8N[n8n]
    DockerVM -- Hosts --> WebUI[Open WebUI]
    DockerVM -- Hosts --> Portainer[Portainer]
    DockerVM -- Hosts --> Monitoring[Monitoring]

    WebUI -- Interacts with --> Ollama
    VLLM_Embed -- Stores embeddings in --> Qdrant
```

---

## 3. Container Implementations

This section provides a detailed breakdown of each container's purpose, key software, resource allocation, and configuration details, sourced directly from `phoenix_lxc_configs.json`.

### Container 801: Embedding Service (granite-embedding)

*   **Purpose**: Hosts a vLLM instance serving the `ibm-granite/granite-embedding-english-r2` model.
*   **Key Software**: vLLM
*   **Resource Allocation**:
    *   **CPU**: 6 cores
    *   **Memory**: 72000 MB
    *   **Storage**: 128 GB
    *   **GPU**: Passthrough of GPU `0`
*   **Configuration Details**:
    *   **IP Address**: `10.0.0.141`
    *   **Port**: `8000`
    *   **Dependencies**: `101`

### Container 950: vLLM Chat Service (`vllm-qwen2.5-7b-awq`)

*   **Purpose**: Hosts a vLLM instance serving the `Qwen/Qwen2.5-7B-Instruct-AWQ` model for high-performance chat completions.
*   **Key Software**: vLLM
*   **Resource Allocation**:
    *   **CPU**: 6 cores
    *   **Memory**: 72000 MB
    *   **Storage**: 128 GB
    *   **GPU**: Passthrough of GPU `0`
*   **Configuration Details**:
    *   **IP Address**: `10.0.0.150`
    *   **Port**: `8000`
    *   **Model**: `Qwen/Qwen2.5-7B-Instruct-AWQ`
    *   **Configuration**: Managed by a `vllm_engine_config` object in `phoenix_lxc_configs.json`.

### Container 951: Embedding Service (`vllm-granite-embed-r2`)

*   **Purpose**: Hosts a vLLM instance serving the `ibm-granite/granite-embedding-english-r2` model for generating text embeddings.
*   **Key Software**: vLLM
*   **Resource Allocation**:
    *   **CPU**: 6 cores
    *   **Memory**: 72000 MB
    *   **Storage**: 128 GB
    *   **GPU**: Passthrough of GPU `0`
*   **Configuration Details**:
    *   **IP Address**: `10.0.0.151`
    *   **Port**: `8000`
    *   **Configuration**: Managed by a `vllm_engine_config` object in `phoenix_lxc_configs.json`.

### Container 952: Vector Database (`qdrant-VSCodeRag`)

*   **Purpose**: Provides a high-performance, scalable vector database for storing and searching text embeddings.
*   **Key Software**: Qdrant (via Docker)
*   **Resource Allocation**:
    *   **CPU**: 2 cores
    *   **Memory**: 2048 MB
    *   **Storage**: 32 GB
*   **Configuration Details**:
    *   **IP Address**: `10.0.0.152`
    *   **Port**: `6333`
    *   **Data Persistence**: Data is stored in a dedicated 20GB volume mounted at `/qdrant/storage`.

### Container 101: API Gateway (`Nginx-VscodeRag`)

*   **Purpose**: Functions as a high-performance reverse proxy and API gateway, serving as the central, secure entry point for all backend services, including routing to the vLLM service.
*   **Key Software**: Nginx
*   **Resource Allocation**:
    *   **CPU**: 4 cores
    *   **Memory**: 4096 MB
    *   **Storage**: 32 GB
*   **Configuration Details**:
    *   **IP Address**: `10.0.0.153`
    *   **Functionality**:
        *   Routes requests to backend services based on hostname and request path.
        *   Manages SSL termination.
        *   Routes to the vLLM embedding service.

### Container 955: Ollama Service (`ollama-oWUI`)

*   **Purpose**: Provides a standardized, GPU-accelerated base for running Ollama models.
*   **Key Software**: Ollama
*   **Resource Allocation**:
    *   **CPU**: 6 cores
    *   **Memory**: 32768 MB
    *   **Storage**: 128 GB
    *   **GPU**: Passthrough of GPU `0`
*   **Configuration Details**:
    *   **IP Address**: `10.0.0.155`
    *   **Port**: `11434`

### Container 957: Llama.cpp Service (`llamacpp`)

*   **Purpose**: Provides a GPU-accelerated environment for compiling and running models with `llama.cpp`.
*   **Key Software**: `llama.cpp`
*   **Resource Allocation**:
    *   **CPU**: 6 cores
    *   **Memory**: 32768 MB
    *   **Storage**: 128 GB
    *   **GPU**: Passthrough of GPU `1`
*   **Configuration Details**:
    *   **IP Address**: `10.0.0.157`
    *   **Port**: `8081` (if server is run)
    *   **Compilation**: Compiled with cuBLAS support for NVIDIA GPUs.

---

## 4. Advanced Configuration Patterns

### 4.1. The Application Script Pattern

A key architectural pattern in the Phoenix Hypervisor is the use of an `application_script` defined in `phoenix_lxc_configs.json`. This pattern separates the installation of a feature's dependencies from its runtime configuration and execution.

*   **Feature Script (`lxc_setup/`)**: Responsible for installing the necessary software and libraries (e.g., `phoenix_hypervisor_feature_install_vllm.sh` installs vLLM, PyTorch, etc.). This script prepares the container with all the required tools.
*   **Application Script (`bin/`)**: Responsible for taking the declarative configuration from `phoenix_lxc_configs.json` and dynamically generating the runtime environment. For example, `phoenix_hypervisor_lxc_vllm.sh` reads the `vllm_engine_config` object, generates a systemd service file, and starts the vLLM server.

This separation of concerns ensures that our feature scripts are modular and reusable, while the application scripts provide a powerful mechanism for declarative, runtime configuration. The recent refactoring of the vLLM deployment serves as the canonical example of this pattern.