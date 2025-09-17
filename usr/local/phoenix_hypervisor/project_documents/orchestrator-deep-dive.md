---
title: "Phoenix Orchestrator: A Deep Dive"
summary: This document provides a detailed analysis of the `phoenix_orchestrator.sh` script's workflow, illustrating the sequence of operations for provisioning and configuring a container.
document_type: Technical
status: Draft
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Team/Individual Name
tags:
- Phoenix Hypervisor
- Architecture
- LXC
- Orchestration
- Workflow
review_cadence: Annual
---

## 1. Introduction

The `phoenix_orchestrator.sh` script is the heart of the Phoenix Hypervisor project. It is a sophisticated, idempotent script that manages the entire lifecycle of LXC containers and VMs, from creation to configuration. This document provides a detailed breakdown of its operational workflow.

## 2. Orchestrator Workflow

The following diagram illustrates the sequence of operations for provisioning and configuring a container.

```mermaid
graph TD
    A[Start: phoenix_orchestrator.sh CTID] --> B{Container Exists?};
    B -- No --> C{Clone or Template?};
    B -- Yes --> G[Skip Creation];
    C -- clone_from_ctid defined --> D[Clone Container];
    C -- template defined --> E[Create from Template];
    D --> F[Apply Configurations];
    E --> F;
    F --> H{Container Running?};
    H -- No --> I[Start Container];
    H -- Yes --> J[Skip Start];
    I --> K[Apply Features];
    J --> K;
    K --> L[Run Application Script];
    L --> M[Create Snapshot if Template];
    M --> N[End];