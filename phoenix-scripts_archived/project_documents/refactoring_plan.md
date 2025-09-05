# High-Level Refactoring Plan for phoenix-scripts

## 1. Introduction

This document outlines the high-level refactoring plan for the `phoenix-scripts` project. The primary goal is to modernize the existing scripts by integrating them into the `phoenix_hypervisor` project and adopting its robust, modular, and configuration-driven architecture. This will result in a single, unified system for managing both the hypervisor setup and the subsequent creation of LXC containers.

This plan is based on the synthesis of two key documents:
*   `phoenix-scripts/project_documents/initial_analysis.md`
*   `phoenix_hypervisor/project_documents/model_analysis.md`

The refactoring process will be divided into four key phases: Project Unification, Configuration Migration, Script Modularization, and Orchestrator Enhancement.

## 2. Phase 1: Project Unification

The first step is to merge the functionality of `phoenix-scripts` into the `phoenix_hypervisor` project structure. This will create a single, cohesive codebase.

*   **Action:** All logic and configuration from `phoenix-scripts` will be moved into the `phoenix_hypervisor` directory structure.
*   **New Structure:**
    *   `phoenix_hypervisor/bin/hypervisor_setup/`: This new directory will contain the refactored, modular scripts responsible for setting up the Proxmox host.
    *   `phoenix_hypervisor/bin/lxc_setup/`: The existing feature scripts for LXC containers will be moved here to distinguish them from hypervisor tasks.
    *   `phoenix_hypervisor/etc/`: This directory will house the new JSON configuration file for the hypervisor setup.
*   **Outcome:** The `phoenix-scripts` directory will be decommissioned, and all development will continue within the `phoenix_hypervisor` project.

## 3. Phase 2: Configuration Migration

This phase focuses on replacing the brittle, shell-based configuration with a robust, schema-validated JSON format.

*   **Action:** Create a new configuration file, `phoenix_hypervisor/etc/hypervisor_config.json`, and a corresponding schema, `hypervisor_config.schema.json`.
*   **Migration:**
    *   All variables currently defined in `phoenix_config.sh` (e.g., ZFS pool layouts, dataset properties, network settings, user configurations) will be translated into a structured JSON format.
    *   The new schema will enforce data types, required fields, and valid value formats, preventing configuration errors before execution.
*   **Outcome:** Configuration will be decoupled from execution logic, making the system easier to manage and validate. The orchestrator will read from this new JSON file instead of sourcing a shell script.

## 4. Phase 3: Script Modularization

The core of the refactoring involves decomposing the large, monolithic scripts from `phoenix-scripts` into small, single-purpose, reusable feature scripts.

*   **Action:** Each major function of the original scripts will be extracted into its own feature script within `phoenix_hypervisor/bin/hypervisor_setup/`.
*   **Decomposition Plan:** To ensure clarity and avoid any confusion with LXC feature scripts, all new hypervisor-level scripts will be prefixed with `hypervisor_`.
    *   `phoenix_proxmox_initial_setup.sh` → `hypervisor_initial_setup.sh`
    *   `phoenix_install_nvidia_driver.sh` → `hypervisor_feature_install_nvidia.sh`
    *   `phoenix_create_admin_user.sh` → `hypervisor_feature_create_admin_user.sh`
    *   `phoenix_setup_zfs_pools.sh` & `phoenix_setup_zfs_datasets.sh` → `hypervisor_feature_setup_zfs.sh`
    *   `phoenix_create_storage.sh` → (Functionality will be merged into `hypervisor_feature_setup_zfs.sh`)
    *   `phoenix_setup_nfs.sh` → `hypervisor_feature_setup_nfs.sh`
    *   `phoenix_setup_samba.sh` → `hypervisor_feature_setup_samba.sh`
*   **Shared Utilities:** All common functions from `common.sh` will be integrated into the existing `phoenix_hypervisor_common_utils.sh` to avoid code duplication.
*   **Outcome:** The system will be composed of small, testable, and maintainable scripts, making it easier to add new features or modify existing ones.

## 5. Phase 4: Orchestrator Unification

The final phase is to unify all functionality under the existing `phoenix_orchestrator.sh`. This aligns with the new strategic direction to have a single, powerful tool for managing the entire lifecycle of the Phoenix environment, from hypervisor setup to LXC provisioning.

*   **Action:** The existing `phoenix_orchestrator.sh` will be enhanced to include a new mode for hypervisor setup.
*   **Implementation:**
    *   A new command-line flag, `--setup-hypervisor`, will be added to the orchestrator.
    *   When this flag is used, the script will:
        1.  Read and validate the `hypervisor_config.json`.
        2.  Execute the new feature scripts from `bin/hypervisor_setup/` in the correct, predefined sequence.
        3.  Incorporate the state-tracking and idempotency logic from the original `create_phoenix.sh` to allow for safe, re-runnable executions.
*   **Outcome:** A single, unified orchestrator will manage both hypervisor and LXC tasks, simplifying the user experience and reducing the number of management scripts.

## 6. New High-Level Workflow

The refactored workflow will use a single, unified orchestrator with different modes for hypervisor setup and LXC provisioning.

```mermaid
graph TD
    subgraph "Unified Orchestration"
        A[Start] --> B{phoenix_orchestrator.sh};
        B -->|--setup-hypervisor| C[Read hypervisor_config.json];
        C --> H1[hypervisor_initial_setup.sh];
        H1 --> H2[hypervisor_feature_install_nvidia.sh];
        H2 --> H3[hypervisor_feature_create_admin_user.sh];
        H3 --> H4[hypervisor_feature_setup_zfs.sh];
        H4 --> H5[hypervisor_feature_setup_nfs.sh];
        H5 --> H6[hypervisor_feature_setup_samba.sh];
        H6 --> Z[End: Hypervisor Setup Complete];

        B -->|--lxc 'CTID'| D[Read phoenix_lxc_configs.json];
        D --> L1[Clone Template];
        L1 --> L2[Execute Feature Scripts];
        L2 --> Y[End: LXC Provisioning Complete];
    end