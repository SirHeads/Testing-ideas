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
  - "Traefik"
  - "Step-CA"
  - "Ollama"
  - "n8n"
  review_cadence: "Annual"
last_reviewed: "2025-09-29"
---

# LXC Container Implementation Guide

## 1. Overview

This document provides a single, authoritative, and RAG-optimized overview of all LXC Container Implementations within the Phoenix Hypervisor project. It synthesizes information from numerous planning and implementation documents, cross-referenced with the `phoenix_lxc_configs.json` file to establish a ground truth for each container's configuration and purpose.

## 2. System Architecture

The LXC containers operate within a unified network bridge (`vmbr0`) and are part of a three-tiered networking model. This model consists of an Nginx gateway for external traffic, a Traefik proxy for the internal service mesh, and a Step-CA for automated certificate management.

### High-Level Interaction Diagram

```mermaid
graph TD
    subgraph "External Network"
        A[Client]
    end

    subgraph "Phoenix Hypervisor"
        subgraph "Gateway Layer"
            B[LXC 101: Nginx Gateway]
        end

        subgraph "Internal Service Mesh"
            C[LXC 102: Traefik Proxy]
            D[LXC 103: Step-CA]
        end

        subgraph "Application Layer"
            E[VM 1001: Portainer]
            F[VM 1002: Dr-Phoenix]
            G[Other Services]
        end
    end

    A -- HTTPS --> B
    B -- Routes Traffic --> C
    C -- Routes to --> E
    C -- Routes to --> F
    C -- Routes to --> G
    D -- Issues Certificates --> C
    C -- Provides Certificates --> E
    C -- Provides Certificates --> F
    C -- Provides Certificates --> G
```

---

## 3. Container Implementations

This section provides a detailed breakdown of each container's purpose, key software, resource allocation, and configuration details, sourced directly from `phoenix_lxc_configs.json`.

### VM 1002: Dr-Phoenix

*   **Purpose**: Hosts all Dockerized services, which are now managed as declarative stacks.
*   **Key Software**: Docker
*   **Declarative Stacks**: This VM is configured to run a variety of Docker stacks, as defined in `phoenix_vm_configs.json` and `phoenix_stacks_config.json`. These stacks include services such as Qdrant, vLLM, Ollama, and n8n.
*   **Resource Allocation**:
    *   **CPU**: 4 cores
    *   **Memory**: 4096 MB
    *   **Storage**: 64 GB
*   **Configuration Details**:
    *   **IP Address**: `10.0.0.102`
    *   **Data Persistence**: Data is managed by Docker volumes within the stacks.

---

### LXC 101: Nginx Gateway

*   **Purpose**: Acts as the primary external-facing Nginx reverse proxy and API gateway.
*   **Key Software**: Nginx
*   **Resource Allocation**:
    *   **CPU**: 4 cores
    *   **Memory**: 4096 MB
    *   **Storage**: 32 GB
*   **Configuration Details**:
    *   **IP Address**: `10.0.0.153`
    *   **Data Persistence**: Logs are stored in a dedicated ZFS volume.

### LXC 102: Traefik Internal Proxy

*   **Purpose**: Acts as an internal service mesh and reverse proxy, with automatic certificate management.
*   **Key Software**: Traefik
*   **Resource Allocation**:
    *   **CPU**: 2 cores
    *   **Memory**: 2048 MB
    *   **Storage**: 16 GB
*   **Configuration Details**:
    *   **IP Address**: `10.0.0.12`
    *   **Data Persistence**: Configuration is stored in a dedicated ZFS volume.

### LXC 103: Step-CA

*   **Purpose**: Hosts a Smallstep Step-CA instance, which serves as the internal certificate authority.
*   **Key Software**: Step-CA
*   **Resource Allocation**:
    *   **CPU**: 2 cores
    *   **Memory**: 1024 MB
    *   **Storage**: 16 GB
*   **Configuration Details**:
    *   **IP Address**: `10.0.0.10`
    *   **Data Persistence**: SSL certificates and other CA data are stored in a dedicated ZFS volume.

---

## 4. Advanced Configuration Patterns

### 4.1. The Application Script Pattern

A key architectural pattern in the Phoenix Hypervisor is the use of an `application_script` defined in `phoenix_lxc_configs.json`. This pattern separates the installation of a feature's dependencies from its runtime configuration and execution.

*   **Feature Script (`lxc_setup/`)**: Responsible for installing the necessary software and libraries (e.g., `phoenix_hypervisor_feature_install_vllm.sh` installs vLLM, PyTorch, etc.). This script prepares the container with all the required tools.
*   **Application Script (`bin/`)**: Responsible for taking the declarative configuration from `phoenix_lxc_configs.json` and dynamically generating the runtime environment. For example, `phoenix_hypervisor_lxc_vllm.sh` reads the `vllm_engine_config` object, generates a systemd service file, and starts the vLLM server.

This separation of concerns ensures that our feature scripts are modular and reusable, while the application scripts provide a powerful mechanism for declarative, runtime configuration. The recent refactoring of the vLLM deployment serves as the canonical example of this pattern.