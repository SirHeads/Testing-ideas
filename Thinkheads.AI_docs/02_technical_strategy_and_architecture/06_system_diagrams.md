---
title: System Diagrams
summary: A centralized document containing Mermaid diagrams of the high-level system architecture, network topology, and data flow.
document_type: Technical Strategy
status: Approved
version: 2.0.0
author: Thinkheads.AI
owner: Technical VP
tags:
  - Diagrams
  - Architecture
  - Mermaid
  - Workflow
  - Orchestration
review_cadence: Quarterly
last_reviewed: 2025-09-29
---

# System Diagrams

This document contains Mermaid diagrams of the high-level system architecture, network topology, and data flow.

## High-Level System Architecture

```mermaid
graph TD
    subgraph "User"
        A[Developer/Admin]
    end

    subgraph "Phoenix Hypervisor (Proxmox Host)"
        B[phoenix_orchestrator.sh]
        C[/etc/phoenix_hypervisor_config.json]
        D[/etc/phoenix_lxc_configs.json]
        E[LXC Containers]
        F[Virtual Machines]
    end

    A -- Manages --> B
    B -- Reads --> C
    B -- Reads --> D
    B -- Provisions/Manages --> E
    B -- Provisions/Manages --> F
```

## Phoenix Orchestrator Workflow

```mermaid
graph TD
    A[Start] --> B{Parse Arguments};
    B --> C{Mode?};
    C -- Hypervisor Setup --> D[Execute Hypervisor Setup Scripts];
    C -- LXC Orchestration --> E[Validate Inputs];
    E --> F[Ensure Container Defined];
    F --> G[Apply Configurations];
    G --> H[Start Container];
    H --> I[Apply Features];
    I --> J[Run Application Script];
    J --> K[Run Health Checks];
    K --> L[Create Snapshots];
    L --> M[End];
    D --> M;