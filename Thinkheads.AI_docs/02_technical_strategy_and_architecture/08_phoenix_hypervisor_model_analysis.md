---
title: 'Architectural Model: The Phoenix Hypervisor'
summary: A detailed architectural analysis of the phoenix_hypervisor project, establishing it as the model for future refactoring efforts. This document outlines key design patterns, structural improvements, and the orchestration strategy that ensure robustness and maintainability.
document_type: Analysis
status: Approved
version: '1.2'
author: Roo
owner: Thinkheads.AI
tags:
  - Phoenix Hypervisor
  - Architecture
  - Analysis
  - Refactoring
  - Modularity
  - Orchestration
  - Configuration Management
  - IaC
review_cadence: Annual
last_reviewed: '2025-09-30'
---

## Introduction

This document presents an architectural analysis of the `phoenix_hypervisor` project. The goal is to identify and document the key design patterns and structural improvements that make it a robust, maintainable, and scalable system. This analysis will serve as the definitive model for the refactoring of the legacy `phoenix-scripts` project and as a guide for all future infrastructure-as-code (IaC) initiatives.

The analysis focuses on four key areas:
1.  **Project Structure**: The logical organization of files and directories.
2.  **Configuration Management**: The strategy for defining and managing system state.
3.  **Modularity and Reusability**: The approach to breaking down logic into reusable components.
4.  **Orchestration Strategy**: The mechanism for executing and coordinating tasks.

## Key Architectural Pillars

The `phoenix_hypervisor` project embodies a mature and robust architecture that offers significant advantages over the legacy `phoenix-scripts`.

### 1. Unified Project Structure

`phoenix_hypervisor` employs a clean, well-defined directory structure that enforces a strong separation of concerns:

*   **`/bin`**: Contains all executable logic, including the central `phoenix` CLI, specialized manager scripts, and shared utilities.
*   **`/etc`**: Contains all configuration data, stored in schema-validated JSON files. This includes definitions for the hypervisor, LXC containers, and VMs.
*   **`Thinkheads.AI_docs/`**: The centralized repository for all architectural, strategic, and project-related documentation.

This structure makes the project easy to navigate and maintain, as the role of each component is immediately clear.

### 2. Centralized, Schema-Driven Configuration

The most significant architectural improvement is the shift from scattered shell variables to a centralized, schema-driven JSON configuration.

*   **`phoenix-scripts` (Legacy)**: Relied on shell variables defined in files like `phoenix_config.sh`, which are sourced by other scripts. This approach is error-prone, lacks data validation, and tightly couples configuration to execution logic.
*   **`phoenix_hypervisor` (Model)**: Utilizes a set of dedicated JSON files for managing state:
    *   `phoenix_hypervisor_config.json`: Defines global settings, ZFS configuration, network settings, and hypervisor-level features.
    *   `phoenix_lxc_configs.json`: Contains detailed definitions for each LXC container, including resources, features, and application-specific scripts.
    *   `phoenix_vm_configs.json`: Contains definitions for QEMU/KVM virtual machines.

These files are validated against corresponding JSON schemas (`*.schema.json`), ensuring data integrity and preventing common configuration errors. This decouples the **"what"** (the desired state defined in JSON) from the **"how"** (the execution logic in the shell scripts).

### 3. High Modularity and Reusability

`phoenix_hypervisor` is built on a foundation of small, single-purpose scripts, which promotes reusability, testability, and extensibility.

*   **Feature Scripts**: Each distinct piece of functionality is encapsulated in its own script. This is applied at two levels:
    *   **Hypervisor Setup**: Scripts like `hypervisor_feature_setup_zfs.sh` and `hypervisor_feature_install_nvidia.sh` handle specific setup tasks on the host.
    *   **Guest Provisioning**: Scripts like `phoenix_hypervisor_feature_install_docker.sh` and `..._install_vllm.sh` install and configure software inside LXC containers or VMs.
*   **Shared Utilities**: Common functions for logging, error handling, command execution, and JSON parsing are centralized in `phoenix_hypervisor_common_utils.sh`.
*   **Template Inheritance**: The `clone_from_ctid` and `clone_from_vmid` mechanisms allow for the creation of hierarchical templates.

### 4. Intelligent Orchestration

The orchestration in `phoenix_hypervisor` is handled by an intelligent entry point that manages the entire lifecycle of the system.

*   **Central Orchestrator**: The `phoenix` CLI is the single point of entry for all provisioning and management tasks. It reads the configuration files and drives the entire workflow in a predictable, repeatable manner.
*   **Dispatcher-Manager Architecture**: The `phoenix` script acts as a dispatcher, routing commands to specialized manager scripts (`hypervisor-manager.sh`, `lxc-manager.sh`, `vm-manager.sh`).
*   **Verb-First CLI**: The CLI uses an intuitive, verb-first command structure (e.g., `phoenix setup`, `phoenix create <ID>`).
*   **Stateless and Idempotent**: The orchestrator is designed to be stateless and idempotent. It checks the current state of the system at each step and only performs the actions necessary to reach the desired state defined in the configuration.

## Recommendations for `phoenix-scripts` Refactoring

Based on this analysis, the following recommendations are mandated for the `phoenix-scripts` refactoring to align it with the `phoenix_hypervisor` model:

1.  **Adopt the Unified Directory Structure**: Reorganize the project into `bin/`, `etc/`, and `Thinkheads.AI_docs/` directories.
2.  **Implement Centralized JSON Configuration**: Replace the `phoenix_config.sh` file with a set of schema-validated JSON files.
3.  **Decompose Scripts into Modules**: Break down large, monolithic scripts into smaller, single-responsibility feature scripts and centralize common functions.
4.  **Unify Orchestration**: Implement a central `phoenix` CLI that acts as a dispatcher to specialized manager scripts.

By adopting these architectural patterns, the `phoenix-scripts` project will be transformed into a more robust, maintainable, and scalable system, in line with our engineering principles.
