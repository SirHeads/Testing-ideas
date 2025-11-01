# Phoenix Hypervisor: A Comprehensive Architectural Review

## 1. Introduction

This document provides a detailed architectural overview of the Phoenix Hypervisor environment. The system is a sophisticated "functional toolbox" that leverages Proxmox, LXC containers, and QEMU/KVM VMs to provide a flexible and powerful platform for a variety of workloads, including AI/ML model serving, container management, and core infrastructure services.

## 2. Core Architectural Principles

The Phoenix Hypervisor is built on a foundation of declarative, idempotent, and convergent design principles. The entire system is defined as code, with JSON configuration files serving as the single source of truth. The orchestration engine, driven by the `phoenix-cli`, ensures that the live system consistently converges to the state defined in these files.

## 3. System Architecture Diagram

The following diagram illustrates the high-level architecture of the Phoenix Hypervisor environment, showing the relationships between the core infrastructure components, the AI/ML model serving layer, and the container management platform.

```mermaid
graph TD
    subgraph Proxmox Host
        A[Proxmox VE]
    end

    subgraph Core Infrastructure
        B[LXC 103: Step-CA] -- Issues Certs --> C
        C[LXC 102: Traefik] -- Routes Traffic --> D
        D[LXC 101: Nginx Gateway] -- Exposes Services --> E[External Network]
    end

    subgraph Container Management
        F[VM 1001: Portainer Server] -- Manages --> G
        G[VM 1002: drphoenix (Portainer Agent)] -- Runs --> H{Docker Stacks}
    end

    subgraph AI/ML Model Serving
        I[LXC 801: granite-embedding] -- Served by --> C
        J[LXC 802: granite-3.3-8b-fp8] -- Served by --> C
        K[LXC 914: ollama-gpu0] -- Served by --> C
        L[LXC 917: llamacpp-gpu0] -- Served by --> C
    end

    subgraph Base Templates
        M[LXC 900: Base OS]
        N[LXC 901: Base OS + CUDA]
        O[VM 9000: Ubuntu Cloud Template]
    end

    %% Relationships
    C -- Manages Certs with --> B
    F -- Depends on --> C
    G -- Depends on --> F
    H -- Includes --> P[Qdrant]
    H -- Includes --> Q[Thinkheads.AI App]
    I -- Cloned from --> N
    J -- Cloned from --> N
    K -- Cloned from --> N
    L -- Cloned from --> N
    B -- Cloned from --> M
    C -- Cloned from --> M
    D -- Cloned from --> M
    F -- Cloned from --> O
    G -- Cloned from --> O
```

## 4. Component Breakdown

### 4.1. Core Infrastructure

*   **LXC 103: Step-CA**: The heart of the internal Public Key Infrastructure (PKI). It is responsible for issuing and managing TLS certificates for all internal services, ensuring secure communication throughout the environment.
*   **LXC 102: Traefik**: The primary internal reverse proxy and load balancer. It dynamically discovers and routes traffic to the appropriate backend services, including the AI/ML models and the Portainer management UI. It also handles ACME challenges with Step-CA to automate certificate management.
*   **LXC 101: Nginx Gateway**: The main entry point for all external traffic. It acts as a secure gateway, proxying requests to the internal Traefik instance.

### 4.2. Container Management

*   **VM 1001: Portainer Server**: The central management UI for the Docker environment. It provides a web-based interface for deploying, managing, and monitoring Docker stacks.
*   **VM 1002: drphoenix (Portainer Agent)**: A dedicated VM that runs the Portainer agent and hosts the Docker stacks managed by the Portainer server. This includes the Qdrant vector database and the main Thinkheads.AI web application.

### 4.3. AI/ML Model Serving

The Phoenix Hypervisor is designed to serve a variety of AI/ML models, each running in its own dedicated LXC container with GPU passthrough for hardware acceleration.

*   **LXC 801: granite-embedding**: Serves the `ibm-granite/granite-embedding-english-r2` model for generating text embeddings.
*   **LXC 802: granite-3.3-8b-fp8**: Serves the `Qwen/Qwen3-4B-Thinking-2507-FP8` model, a powerful language model with FP8 quantization for efficient inference.
*   **LXC 914: ollama-gpu0**: Provides an endpoint for the Ollama model serving framework.
*   **LXC 917: llamacpp-gpu0**: Provides an endpoint for the Llama.cpp model serving framework.

### 4.4. Base Templates

The entire system is built upon a set of base templates, which ensures consistency and reproducibility.

*   **LXC 900: Base OS**: A minimal Ubuntu 24.04 template with essential packages and a standardized locale.
*   **LXC 901: Base OS + CUDA**: An extension of the base OS template that includes the NVIDIA user-space drivers and CUDA toolkit, serving as the foundation for all GPU-accelerated containers.
*   **VM 9000: Ubuntu Cloud Template**: A minimal Ubuntu 24.04 cloud image that serves as the base for all VMs.

## 5. Conclusion

The Phoenix Hypervisor is a well-architected and highly automated platform that provides a robust and flexible "functional toolbox" for a wide range of applications. Its declarative nature, combined with a clear separation of concerns between the different components, makes it a powerful and maintainable system for managing complex virtualized environments.