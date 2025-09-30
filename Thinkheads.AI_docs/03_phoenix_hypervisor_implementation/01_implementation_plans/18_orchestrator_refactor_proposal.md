---
title: Orchestrator Refactoring Proposal for Phoenix Hypervisor
summary: A proposal to refactor the monolithic phoenix_orchestrator.sh script into a modular, plugin-based architecture to improve maintainability, testability, and extensibility.
document_type: Implementation Plan
status: Proposed
version: 1.0.0
author: Roo
owner: Technical VP
tags:
  - Phoenix Hypervisor
  - Orchestration
  - Architecture
  - Refactoring
review_cadence: Ad-Hoc
last_reviewed: 2025-09-30
---

# Proposal: Refactoring to a Modular Orchestrator

## 1. Introduction

The `phoenix_orchestrator.sh` script has been instrumental in automating the Phoenix Hypervisor. However, its monolithic design is accumulating technical debt. To ensure the long-term health and scalability of our automation, we must refactor the orchestrator into a more modular and maintainable architecture.

This document proposes a shift from a single, large bash script to a plugin-based orchestration engine.

## 2. Current State Analysis

**Architecture:** A single, 1300+ line bash script (`phoenix_orchestrator.sh`) that contains all logic for hypervisor setup, LXC/VM lifecycle management, feature installation, and more.

**Strengths:**
*   **Functional:** It successfully orchestrates the entire system.
*   **Idempotent:** The core state machine logic is sound.

**Weaknesses:**
*   **Maintainability:** The script is difficult to navigate and modify. A small change can have unintended consequences.
*   **Testability:** Unit testing a large bash script is notoriously difficult, leading to a reliance on slow, end-to-end integration tests.
*   **Extensibility:** Adding new functionality (e.g., support for a new storage backend, a different virtualization technology) is complex and risky.
*   **Language Limitations:** While powerful, bash is not the ideal language for complex logic, error handling, and data manipulation.

## 3. Proposed Architecture: A Plugin-Based Engine

I propose refactoring the orchestrator into a core engine with a plugin-based architecture. This could be implemented in a more robust language like Python, which is well-suited for this type of task.

**Proposed Structure:**

*   **Core Engine (`phoenix_engine.py`):**
    *   Handles command-line argument parsing.
    *   Manages the configuration loading and merging (as per the modular configuration proposal).
    *   Executes the orchestration lifecycle (e.g., `define`, `configure`, `start`, `validate`).
    *   Discovers and loads plugins from a dedicated `plugins/` directory.

*   **Plugins (`plugins/*.py`):**
    *   Each plugin would be responsible for a specific domain of functionality.
    *   Examples:
        *   `lxc.py`: Handles all `pct` commands and LXC lifecycle management.
        *   `vm.py`: Handles all `qm` commands and VM lifecycle management.
        *   `zfs.py`: Manages ZFS pool and dataset operations.
        *   `features.py`: Manages the installation of features like Docker and NVIDIA drivers.
        *   `validation.py`: Runs health checks and tests.

### 3.1. "After" Architecture Diagram

This diagram illustrates the proposed plugin-based architecture.

```mermaid
graph TD
    subgraph User Interface
        A[CLI: phoenix-ng --id 950]
    end

    subgraph Core Engine (Python)
        B[phoenix_engine.py]
        C[Plugin Loader]
        D[Lifecycle Executor]
    end

    subgraph Plugins
        P1[lxc.py]
        P2[vm.py]
        P3[zfs.py]
        P4[features.py]
        P5[validation.py]
    end

    A --> B
    B --> C
    B --> D
    C -- Discovers & Loads --> P1
    C -- Discovers & Loads --> P2
    C -- Discovers & Loads --> P3
    C -- Discovers & Loads --> P4
    C -- Discovers & Loads --> P5
    
    D -- Calls --> P1
    D -- Calls --> P2
    D -- Calls --> P3
    D -- Calls --> P4
    D -- Calls --> P5

    style B fill:#f9f,stroke:#333,stroke-width:2px
```

## 4. Goals and Gains

### Goals

*   **Decouple Logic:** Separate the core orchestration flow from the implementation details of specific tasks.
*   **Improve Testability:** Enable unit testing for individual plugins.
*   **Enhance Extensibility:** Make it simple to add new functionality by creating new plugins.
*   **Increase Robustness:** Leverage a more powerful language for error handling, logging, and data structures.

### Gains

*   **Maintainability:** The codebase will be cleaner, more organized, and easier to reason about.
*   **Faster Development:** Changes can be made to individual plugins with more confidence and less risk of breaking unrelated functionality.
*   **Improved Reliability:** Unit tests will catch bugs earlier in the development cycle.
*   **Future-Proofing:** The plugin architecture makes it easier to adapt to new technologies and requirements.

## 5. Next Steps

This is a significant but important undertaking. If approved, the first step would be to develop a proof-of-concept for the core engine and a single plugin (e.g., `lxc.py`). We can then incrementally migrate functionality from the old orchestrator to the new, plugin-based model, running them in parallel during the transition to ensure a smooth cutover.