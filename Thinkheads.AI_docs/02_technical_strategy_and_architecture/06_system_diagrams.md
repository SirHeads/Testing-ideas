---
title: System Diagrams
summary: A centralized document containing Mermaid diagrams of the high-level system architecture, network topology, and data flow for the Phoenix Hypervisor project.
document_type: Technical Strategy
status: Approved
version: 2.1.0
author: Thinkheads.AI
owner: Technical VP
tags:
  - Diagrams
  - Architecture
  - Mermaid
  - Workflow
  - Orchestration
  - Phoenix Hypervisor
review_cadence: Quarterly
last_reviewed: 2025-09-29
---

# System Diagrams

This document contains Mermaid diagrams that illustrate the high-level system architecture, the detailed workflow of the `phoenix_orchestrator.sh` script, and the container templating strategy.

## High-Level System Architecture

This diagram provides a comprehensive overview of the Phoenix Hypervisor ecosystem, including user interaction, orchestration, configuration management, and the virtualized resources.

```mermaid
graph TD
    subgraph "User"
        A[Developer/Admin]
    end

    subgraph "Phoenix Hypervisor (Proxmox Host)"
        B[phoenix_orchestrator.sh]
        C[Configuration Files]
        D[LXC Containers]
        E[Virtual Machines]
        F[Storage Pools]
        G[Networking]
    end

    subgraph "Configuration Files"
        C1[/etc/phoenix_hypervisor_config.json]
        C2[/etc/phoenix_lxc_configs.json]
        C3[/etc/phoenix_vm_configs.json]
    end

    A -- Manages --> B
    B -- Reads --> C1
    B -- Reads --> C2
    B -- Reads --> C3
    B -- Provisions/Manages --> D
    B -- Provisions/Manages --> E
    B -- Manages --> F
    B -- Configures --> G
```

## Phoenix Orchestrator Workflow

This diagram details the state machine logic of the `phoenix_orchestrator.sh` script, showing the distinct execution paths for hypervisor setup, LXC container orchestration, and VM provisioning.

```mermaid
graph TD
    A[Start] --> B{Parse Arguments};
    B --> C{Mode?};
    C -- --setup-hypervisor --> D[Execute Hypervisor Setup Scripts];
    C -- LXC ID --> E[Validate LXC Inputs];
    E --> F[Ensure Container Defined];
    F --> G[Apply Configurations];
    G --> H[Start Container];
    H --> I[Apply Features];
    I --> J[Run Application Script];
    J --> K[Run Health Checks];
    K --> L[Create Snapshots];
    L --> M[End];
    D --> M;
    C -- VM ID --> N[Validate VM Inputs];
    N --> O[Ensure VM Defined];
    O --> P[Apply VM Configurations];
    P --> Q[Start VM];
    Q --> R[Wait for Guest Agent];
    R --> S[Apply VM Features via Cloud-Init];
    S --> T[Create VM Snapshot];
    T --> M;
```

## LXC Container Templating Strategy

This diagram illustrates the hierarchical templating and cloning strategy for LXC containers, which ensures a consistent and modular approach to building virtualized environments.

```mermaid
graph TD
    subgraph "Base Templates"
        T1[ubuntu-24.04-standard]
    end

    subgraph "Feature-Specific Templates"
        T2[900: Template-Base]
        T3[901: Template-GPU]
        T4[902: Template-Docker]
        T5[903: Template-Docker-GPU]
    end

    subgraph "Provisioned Containers"
        C1[950: vllm-qwen2.5-7b-awq]
        C2[953: Nginx-VscodeRag]
        C3[955: ollama-oWUI]
        C4[910: Portainer]
    end

    T1 -- Creates --> T2
    T2 -- Cloned to create --> T3
    T2 -- Cloned to create --> T4
    T3 -- Cloned to create --> T5

    T5 -- Cloned to create --> C1
    T2 -- Cloned to create --> C2
    T3 -- Cloned to create --> C3
    T4 -- Cloned to create --> C4