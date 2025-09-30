---
title: "Phase 1 Detailed Requirements: VM Creation MVP"
summary: "This document provides a detailed breakdown of the work required to complete Phase 1 of the VM creation initiative, focusing on the Minimum Viable Product (MVP)."
document_type: "Requirements"
status: "Implemented"
version: "1.0.0"
author: "Roo"
owner: "Project Lead"
tags:
  - "Phoenix Hypervisor"
  - "VM Creation"
  - "Requirements"
  - "Phase 1"
review_cadence: "Ad-hoc"
---

# Phase 1 Detailed Requirements: VM Creation MVP

## 1. Introduction

This document outlines the specific, granular requirements for completing Phase 1 of the VM Creation project. The goal of this phase was to produce a Minimum Viable Product (MVP) that validates the core lifecycle management of a Virtual Machine through the `phoenix` CLI, using a unified command structure that is identical to the existing LXC workflow.

## 2. Detailed Requirements Breakdown

### Task 1: Schema and Configuration Finalization

**Goal:** Formalize the structure for VM definitions within the existing hypervisor configuration file.

-   **Requirement 1.1:** The `phoenix_hypervisor_config.schema.json` file MUST be updated to include a detailed definition for the `vms` array.
-   **Requirement 1.2:** The schema for each object in the `vms` array MUST define and enforce the following properties:
    -   `vmid` (integer, required): The unique ID for the VM.
    -   `name` (string, required): The friendly name and hostname for the VM.
    -   `cores` (integer, required): The number of CPU cores.
    -   `memory_mb` (integer, required): The memory allocation in megabytes.
    -   `disk_size_gb` (integer, required): The size of the root disk in gigabytes.
    -   `storage_pool` (string, required): The Proxmox storage pool for the root disk.
    -   `template_image` (string, required): The full path to the base VM template image.
    -   `network_bridge` (string, required): The network bridge (e.g., `vmbr0`).
-   **Requirement 1.3:** A sample VM definition for an Ubuntu 24.04 server MUST be added to the `phoenix_hypervisor_config.json` file to serve as the primary test case.

### Task 2: Unified Orchestrator Logic

**Goal:** Refactor the `phoenix` CLI to handle both LXC and VM orchestration through a single, unified command.

-   **Requirement 2.1:** The `phoenix` dispatcher MUST be modified to accept a single numeric `<ID>` as the primary positional argument for orchestration.
-   **Requirement 2.2:** All VM-specific flags (`--create-vm`, `--start-vm`, `--stop-vm`, `--delete-vm`) MUST be removed and their logic deprecated.
-   **Requirement 2.3:** A new `delete <ID>` command MUST be introduced to handle the explicit destruction of both LXC containers and VMs.
-   **Requirement 2.4:** The main execution block of the script MUST be updated to include a resource-type detection mechanism:
    -   It will first query `phoenix_lxc_configs.json` for the given `<ID>`.
    -   If found, it will proceed with the existing LXC state machine.
    -   If not found, it will query the `vms` array in `phoenix_hypervisor_config.json` for a matching `vmid`.
    -   If found, it will call the `vm-manager.sh` script.
    -   If the `<ID>` is not found in either configuration file, the script MUST exit with a clear error message stating the ID is undefined.

### Task 3: Core `qm` Integration (VM State Machine)

**Goal:** Implement the backend functions that interact with Proxmox's `qm` command-line tool to manage the VM lifecycle.

-   **Requirement 3.1:** The `vm-manager.sh` script will serve as the state machine for VM provisioning.
-   **Requirement 3.2:** A helper function, `run_qm_command`, MUST be created to execute all `qm` commands. This function MUST respect the global `--dry-run` flag.
-   **Requirement 3.3:** An `ensure_vm_defined` function MUST be created. It will use `qm status` to check if the VM exists. If it does not, it will call a `create_vm` function.
-   **Requirement 3.4:** The `create_vm` function MUST read all necessary parameters from the configuration and construct a valid `qm create` command to generate the VM from the specified `template_image`.
-   **Requirement 3.5:** An `apply_vm_configurations` function MUST use `qm set` to apply the `cores`, `memory`, and other settings from the configuration file to the VM.
-   **Requirement 3.6:** A `start_vm` function MUST be implemented to start the VM using `qm start` if it is not already running.
-   **Requirement 3.7:** A `destroy_vm` function MUST be implemented to stop and destroy a VM using `qm stop` and `qm destroy`. This function will be called when the `delete` command is used.

### Task 4: Basic Cloud-Init Integration

**Goal:** Implement a minimal, static Cloud-Init configuration to allow for basic, automated setup of the new VM.

-   **Requirement 4.1:** The `apply_vm_configurations` function MUST be responsible for configuring the VM's Cloud-Init drive.
-   **Requirement 4.2:** It MUST use `qm set` to attach a `cicustom` drive to the VM.
-   **Requirement 4.3:** For Phase 1, this function will use a static, hardcoded `user-data` configuration that accomplishes the following:
    -   Sets the VM's hostname to the `name` defined in the configuration.
    -   Creates a default administrative user with a pre-defined password and SSH key access.
-   **Requirement 4.4:** The process MUST assume that the `template_image` is Cloud-Init enabled and has the QEMU Guest Agent installed.

## 3. Phase 1 Acceptance Criteria

The successful completion of Phase 1 was determined by the following end-to-end test:

1.  **Creation & Idempotency:**
    -   Running `phoenix create <vmid>` on a non-existent VM successfully creates and starts the VM in Proxmox.
    -   The running VM has the correct resources (cores, memory) and hostname.
    -   It is possible to SSH into the VM using the credentials set by Cloud-Init.
    -   Running `phoenix create <vmid>` a second time results in no changes to the running VM, confirming idempotency.
2.  **Deletion:**
    -   Running `phoenix delete <vmid>` successfully stops and removes the VM from Proxmox.