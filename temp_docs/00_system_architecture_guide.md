---
title: Phoenix Hypervisor System Architecture Guide
summary: This document provides a single, authoritative overview of the Phoenix Hypervisor system architecture, orchestration workflow, and configuration for both VMs and LXC containers.
document_type: Implementation Guide
status: Final
version: "3.0.0"
author: Roo
owner: Developer
tags:
  - Phoenix Hypervisor
  - System Architecture
  - Orchestration
  - LXC
  - VM
  - Proxmox
  - Configuration
review_cadence: Annual
last_reviewed: "2025-10-20"
---

# Phoenix Hypervisor System Architecture Guide

## 1. Overview

The Phoenix Hypervisor project is a robust, declarative, and feature-based system for orchestrating the creation and configuration of LXC containers and Virtual Machines (VMs) on Proxmox. It is specifically tailored for AI and machine learning workloads.

The core of the project is the `phoenix-cli`, an idempotent orchestrator that manages the entire lifecycle of a virtualized resource based on a set of central JSON configuration files that act as a single source of truth.

### 1.1. Key Architectural Concepts

-   **Unified Orchestration**: The `phoenix-cli` provides a single point of entry for managing the hypervisor, LXC containers, and QEMU/KVM VMs.
-   **Declarative Configuration**: All hypervisor, VM, and container specifications are defined in `phoenix_hypervisor_config.json`, `phoenix_vm_configs.json`, `phoenix_lxc_configs.json`, and `phoenix_stacks_config.json`. This provides a clear, version-controllable definition of the desired system state.
-   **Idempotent Orchestration**: The CLI is designed to be stateless and idempotent. Running a command multiple times produces the same result, making deployments resilient and repeatable.
-   **Automated Dependency Resolution**: The CLI automatically builds a dependency graph for all guests and templates, ensuring that resources are created and started in the correct topological order.
-   **Hierarchical Templating**: The system uses a hierarchical, snapshot-based template structure to optimize the creation of both VMs and LXCs, allowing for layered feature inheritance.
-   **Modular Feature Installation**: Guest customization is handled through a series of modular, reusable "feature" scripts (e.g., for installing NVIDIA drivers, Docker, or vLLM).

## 2. System Architecture Diagram

This diagram provides a high-level overview of the entire system, from the CLI to the individual services running within the guests.

```mermaid
graph TD
    subgraph User
        A[User/CI-CD] -- runs --> B{phoenix-cli};
    end

    subgraph Phoenix CLI
        B -- reads --> C{Configuration Files};
        B -- dispatches to --> D[Hypervisor Manager];
        B -- dispatches to --> E[LXC Manager];
        B -- dispatches to --> F[VM Manager];
        B -- dispatches to --> G[Portainer Manager];
    end

    subgraph Configuration [Single Source of Truth]
        C(
            - hypervisor_config.json
            - lxc_configs.json
            - vm_configs.json
            - stacks_config.json
        )
    end

    subgraph Proxmox Hypervisor
        D -- manages --> H[Host Services: ZFS, Firewall, DNS];
        E -- manages --> I[LXC Guests];
        F -- manages --> J[VM Guests];
    end

    subgraph Guests
        subgraph LXC Guests
            I --> I1[Nginx Gateway];
            I --> I2[Traefik Mesh];
            I --> I3[Step-CA];
            I --> I4[AI Models: vLLM, Ollama];
        end
        subgraph VM Guests
            J --> J1[Portainer Server];
            J --> J2[Docker Host w/ Agent];
        end
    end

    subgraph Docker Environment
      G -- manages --> J2;
      J2 -- runs --> K[Docker Stacks: Qdrant, etc.];
    end
```

## 3. Guest Dependency and Template Architecture

The following diagram illustrates the build-time and run-time dependencies between all guest templates and active instances.

```mermaid
graph TD
    subgraph Templates
        T9000["VM Template 9000<br/>ubuntu-2404-cloud-template"];
        T900["LXC Template 900<br/>Copy-Base"];
        T901["LXC Template 901<br/>Copy-Cuda12.8"];
        T910["LXC Template 910<br/>Copy-VLLM-GPUx2"];
        T911["LXC Template 911<br/>Copy-VLLM-GPU0"];
        T912["LXC Template 912<br/>Copy-VLLM-GPU1"];
    end

    subgraph "Tier 1: Core Infrastructure"
        VM1001["VM 1001<br/>Portainer"];
        LXC103["LXC 103<br/>Step-CA"];
        LXC101["LXC 101<br/>Nginx-Phoenix"];
    end

    subgraph "Tier 2: Service Mesh & AI"
        LXC102["LXC 102<br/>Traefik-Internal"];
        VM1002["VM 1002<br/>drphoenix<br/>(Docker Host)"];
        LXC914["LXC 914<br/>ollama-gpu0"];
        LXC917["LXC 917<br/>llamacpp-gpu0"];
    end

    subgraph "Tier 3: AI Model Serving"
        LXC801["LXC 801<br/>granite-embedding"];
        LXC802["LXC 802<br/>granite-3.3-8b-fp8"];
    end

    %% Template Dependencies
    T900 --> T901;
    T901 --> T910;
    T901 --> T911;
    T901 --> T912;

    %% Guest Dependencies
    T9000 -- "clone_from" --> VM1001;
    T9000 -- "clone_from" --> VM1002;
    T900 -- "clone_from" --> LXC103;
    T900 -- "clone_from" --> LXC101;
    T900 -- "clone_from" --> LXC102;
    T901 -- "clone_from" --> LXC914;
    T901 -- "clone_from" --> LXC917;
    T911 -- "clone_from" --> LXC801;
    T911 -- "clone_from" --> LXC802;

    %% Runtime Dependencies
    LXC103 -- "depends_on" --> LXC102;
    LXC101 -- "depends_on" --> LXC914;
    LXC101 -- "depends_on" --> LXC917;
    LXC101 -- "depends_on" --> LXC801;
    LXC101 -- "depends_on" --> LXC802;
```

## 4. Orchestration Workflow

The `phoenix-cli` is the single entry point for all provisioning tasks. It acts as a dispatcher, parsing the user's command, resolving dependencies, and routing tasks to the appropriate manager script (`hypervisor-manager.sh`, `lxc-manager.sh`, `vm-manager.sh`, or `portainer-manager.sh`).

For a detailed breakdown of all available commands, see the **[Phoenix Hypervisor CLI Usage Guide](cli_usage_guide.md)**.

### 4.1. Data Access and Querying

To ensure robust and consistent access to configuration data, all scripts should use the centralized data access functions provided in `phoenix_hypervisor_common_utils.sh`. These functions provide a layer of validation and error handling that prevents silent failures when a configuration value is missing or null.

-   `get_global_config_value <jq_query>`: Retrieves a single value from the main `phoenix_hypervisor_config.json` file.
-   `jq_get_value <ctid> <jq_query>`: Retrieves a single value for a specific LXC container from the `phoenix_lxc_configs.json` file.
-   `jq_get_vm_value <vmid> <jq_query>`: Retrieves a single value for a specific VM from the `phoenix_vm_configs.json` file.
-   `jq_get_array <ctid> <jq_query>`: Retrieves an array of values for a specific LXC container.

**Example Usage:**

```bash
# Get the domain name from the global config
DOMAIN=$(get_global_config_value '.domain_name')

# Get the memory allocation for LXC container 101
MEMORY=$(jq_get_value "101" ".memory_mb")

# Get the list of features for VM 1001
FEATURES=$(jq_get_vm_value "1001" ".features[]")
```