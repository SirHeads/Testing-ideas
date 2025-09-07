---
title: Detailed Implementation Plan for Hypervisor Setup Refactoring
summary: This document provides a detailed, step-by-step implementation plan for refactoring
  the hypervisor setup scripts, focusing on project unification, configuration migration,
  script modularization, and orchestrator unification.
document_type: Strategy | Technical | Business Case | Report
status: Draft | In Review | Approved | Archived
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Team/Individual Name
tags:
- Implementation Plan
- Hypervisor Setup
- Refactoring
- Phoenix Hypervisor
- Project Unification
- Configuration Migration
- Script Modularization
- Orchestrator Unification
review_cadence: Annual | Quarterly | Monthly | None
last_reviewed: YYYY-MM-DD
---
This document provides a detailed, step-by-step implementation plan for refactoring the hypervisor setup scripts. This plan is based on the revised high-level strategy outlined in `phoenix-scripts/project_documents/refactoring_plan.md` and adheres to the critical constraint that all functionality must be a **direct, one-to-one port** of the original `phoenix-scripts`. No changes to package versions, logic, or configurations are permitted without explicit user approval.


## 2. Phase 1: Project Unification

**Objective:** Merge the `phoenix-scripts` project into the `phoenix_hypervisor` directory structure.

*   **Step 1.1: Create New Directories**
    *   Create the `phoenix_hypervisor/bin/hypervisor_setup/` directory.
    *   **Constraint:** This is a structural change only. No functional logic will be introduced in this step.

*   **Step 1.2: Relocate LXC Scripts**
    *   Move the existing LXC feature scripts into the `phoenix_hypervisor/bin/lxc_setup/` directory.
    *   **Constraint:** This is a file relocation task. The scripts themselves must remain unmodified.

*   **Step 1.3: Archive Old Project**
    *   The `phoenix-scripts` directory will be renamed to `phoenix-scripts_archived` to preserve its history.
    *   **Constraint:** No files within the archived directory should be referenced by the new implementation.

## 3. Phase 2: Configuration Migration

**Objective:** Convert the shell-based configuration to a schema-validated JSON format.

*   **Step 2.1: Create JSON Schema**
    *   Create the `phoenix_hypervisor/etc/hypervisor_config.schema.json` file.
    *   Define the schema to enforce types, required fields, and formats for all hypervisor settings.
    *   **Constraint:** The schema must represent a **direct, one-to-one mapping** of the variables in the original `phoenix_config.sh`.

*   **Step 2.2: Create JSON Configuration File**
    *   Create the `phoenix_hypervisor/etc/hypervisor_config.json` file.
    *   Populate this file with the configuration values from `phoenix_config.sh`.
    *   **Constraint:** The values must be identical to the original script. No new default values or logical changes are permitted.

## 4. Phase 3: Script Modularization

**Objective:** Decompose monolithic scripts into single-purpose, modular feature scripts.

*   **Step 3.1: Port `common.sh`**
    *   Integrate all functions from `phoenix-scripts/common.sh` into `phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh`.
    *   **Constraint:** The logic of each function must be a **direct, one-to-one port**.

*   **Step 3.2: Create `hypervisor_initial_setup.sh`**
    *   Create the script at `phoenix_hypervisor/bin/hypervisor_setup/hypervisor_initial_setup.sh`.
    *   Port the functionality from `phoenix_proxmox_initial_setup.sh`.
    *   **Constraint:** This is a direct port. No new features or logic.

*   **Step 3.3: Create `hypervisor_feature_install_nvidia.sh`**
    *   Create the script at `phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_install_nvidia.sh`.
    *   Port the functionality from `phoenix_install_nvidia_driver.sh`.
    *   **Constraint:** This is a direct port. No changes to driver versions or installation methods.

*   **Step 3.4: Create `hypervisor_feature_create_admin_user.sh`**
    *   Create the script at `phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_create_admin_user.sh`.
    *   Port the functionality from `phoenix_create_admin_user.sh`.
    *   **Constraint:** This is a direct port. User properties and permissions must match the original.

*   **Step 3.5: Create `hypervisor_feature_setup_zfs.sh`**
    *   Create the script at `phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_zfs.sh`.
    *   Merge and port the functionality from `phoenix_setup_zfs_pools.sh`, `phoenix_setup_zfs_datasets.sh`, and `phoenix_create_storage.sh`.
    *   **Constraint:** This is a direct port. ZFS properties, pool layouts, and storage configurations must be identical.

*   **Step 3.6: Create `hypervisor_feature_setup_nfs.sh`**
    *   Create the script at `phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_nfs.sh`.
    *   Port the functionality from `phoenix_setup_nfs.sh`.
    *   **Constraint:** This is a direct port. NFS export settings must match the original.

*   **Step 3.7: Create `hypervisor_feature_setup_samba.sh`**
    *   Create the script at `phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_samba.sh`.
    *   Port the functionality from `phoenix_setup_samba.sh`.
    *   **Constraint:** This is a direct port. Samba share configurations must match the original.

## 5. Phase 4: Orchestrator Unification

**Objective:** Enhance the existing `phoenix_orchestrator.sh` to manage the hypervisor setup.

*   **Step 4.1: Add New Command-Line Flag**
    *   Modify `phoenix_hypervisor/bin/phoenix_orchestrator.sh` to accept a new command-line flag: `--setup-hypervisor`.
    *   This flag will trigger the hypervisor setup workflow.
    *   **Constraint:** The existing LXC provisioning functionality must remain the default behavior and be unaffected by these changes.

*   **Step 4.2: Implement Hypervisor Orchestration Logic**
    *   Add a new logic block to the orchestrator that executes when the `--setup-hypervisor` flag is detected.
    *   This block will:
        1.  Read and parse the `hypervisor_config.json` file.
        2.  Execute the `hypervisor_*` feature scripts from `bin/hypervisor_setup/` in the correct, predefined sequence.
        3.  Incorporate the state-tracking and idempotency logic from the original `create_phoenix.sh`.
    *   **Constraint:** The execution order and state management must replicate the behavior of the original `phoenix_fly.sh` and `create_phoenix.sh` scripts precisely.
