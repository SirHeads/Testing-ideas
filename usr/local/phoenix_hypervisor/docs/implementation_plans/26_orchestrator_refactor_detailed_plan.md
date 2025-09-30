---
title: Phoenix Orchestrator Refactor - Detailed Project Plan
summary: A detailed, phased plan for refactoring the phoenix_orchestrator.sh script into a new, modular, verb-first CLI.
document_type: Implementation Plan
status: Draft
version: 1.1.0
author: Roo
owner: Technical VP
tags:
  - Phoenix Hypervisor
  - Orchestration
  - Refactoring
  - Project Plan
  - CLI
review_cadence: Ad-Hoc
last_reviewed: 2025-09-30
---

# Phoenix Orchestrator Refactor: Detailed Project Plan

## 1. Introduction

This document provides a detailed, phased plan for the refactoring of the `phoenix_orchestrator.sh` script. The goal of this project is to transform the current monolithic script into a modular, maintainable, and user-friendly command-line interface (CLI) that aligns with the strategic goals of Thinkheads.AI. This plan is based on the high-level strategy outlined in the `25_orchestrator_refactor_project_charter.md` and the `24_unified_cli_refactor_proposal.md`.

This refactor directly supports our core **Architectural Principles**, particularly **Modularity and Reusability**, by breaking down a single, complex script into smaller, single-purpose components (a dispatcher and multiple managers). This will improve maintainability, reduce cognitive load, and allow for easier extension in the future.

## 2. Phased Implementation

The project will be executed in four distinct phases. This approach will allow for iterative development, testing, and feedback, minimizing the risk of disruption to existing workflows.

### Phase 1: The Dispatcher and Hypervisor Manager

*   **Goal:** Establish the foundational architecture of the new orchestrator by creating the `phoenix` dispatcher and migrating all hypervisor-related logic to a dedicated manager script.
*   **Key Tasks:**
    1.  **Create `bin/phoenix` Dispatcher:**
        *   Implement the core logic to parse the verb (e.g., `create`, `start`, `setup`) and the target ID(s).
        *   Implement a simple routing mechanism to delegate commands to the appropriate manager script.
        *   Implement a `--help` command that provides a basic overview of the new CLI.
    2.  **Create `bin/managers/hypervisor-manager.sh`:**
        *   Migrate all hypervisor-related functions from `phoenix_orchestrator.sh` (e.g., `setup_hypervisor`).
        *   Ensure that the script is self-contained and can be executed independently.
    3.  **Wire the Dispatcher to the Manager:**
        *   Implement the logic in the `phoenix` dispatcher to call `hypervisor-manager.sh` when the `phoenix setup` command is used.
    4.  **Create a Test Suite:**
        *   **Leverage Existing Framework:** Create a new test suite for the hypervisor manager that integrates with our existing `test_runner.sh`.
        *   **Test Scripts:** Develop new test scripts under `bin/tests/hypervisor/` to validate the functionality of `hypervisor-manager.sh`.
        *   **Configuration:** Define the new test suite (e.g., `hypervisor_manager_tests`) in the relevant configuration files to be picked up by the test runner.

### Phase 2: The LXC Manager

*   **Goal:** Migrate all LXC container management logic to a dedicated `lxc-manager.sh` script and implement dependency resolution in the dispatcher.
*   **Key Tasks:**
    1.  **Create `bin/managers/lxc-manager.sh`:**
        *   Migrate all LXC-related functions from `phoenix_orchestrator.sh` (e.g., `create_container_from_template`, `clone_container`, `start_container`).
    2.  **Enhance the Dispatcher:**
        *   Implement the logic to route all `phoenix <verb> <ID>` commands to the `lxc-manager.sh` script when the ID corresponds to an LXC container.
        *   Implement dependency resolution based on the `clone_from_ctid` and `dependencies` properties in the configuration.
        *   Implement execution ordering based on a topological sort of the dependency graph.
    3.  **Create a Test Suite:**
        *   **Leverage Existing Framework:** Develop a comprehensive suite of tests for the `lxc-manager.sh` script.
        *   **Test Scripts:** Create new test scripts under a new directory, `bin/tests/lxc/`, to cover container creation, dependency resolution, and execution ordering.
        *   **Configuration:** Add the new test suite definitions to `phoenix_lxc_configs.json` to be executed by `test_runner.sh`.

### Phase 3: The VM Manager

*   **Goal:** Migrate all VM management logic to a dedicated `vm-manager.sh` script.
*   **Key Tasks:**
    1.  **Create `bin/managers/vm-manager.sh`:**
        *   Migrate all VM-related functions from `phoenix_orchestrator.sh` (e.g., `orchestrate_vm`, `ensure_vm_defined`).
    2.  **Enhance the Dispatcher:**
        *   Implement the logic to route all `phoenix <verb> <ID>` commands to the `vm-manager.sh` script when the ID corresponds to a VM.
        *   Extend the dependency resolution and execution ordering logic to handle mixed lists of LXCs and VMs.
    3.  **Create a Test Suite:**
        *   **Leverage Existing Framework:** Develop a comprehensive suite of tests for the `vm-manager.sh` script.
        *   **Test Scripts:** Create new test scripts under a new directory, `bin/tests/vm/`, using the established testing patterns.
        *   **Configuration:** Add the new test suite definitions to the relevant configuration files.

### Phase 4: Finalization and Deprecation

*   **Goal:** Finalize the new orchestrator, update all documentation, and gracefully deprecate the old `phoenix_orchestrator.sh` script.
*   **Key Tasks:**
    1.  **Implement `phoenix LetsGo`:**
        *   Implement the master command to create and start all defined guests, respecting all dependencies and boot orders.
    2.  **Update Documentation:**
        *   Update all user and developer documentation to reflect the new `phoenix` CLI and its architecture.
    3.  **Create a Backward Compatibility Layer:**
        *   Create a temporary alias or wrapper script that maps the old `phoenix_orchestrator.sh` commands to the new `phoenix` commands. This will ensure a smooth transition for users.
    4.  **Deprecate the Old Script:**
        *   After a suitable transition period, remove the old `phoenix_orchestrator.sh` script.
    5.  **Final End-to-End Testing:**
        *   **Leverage Existing Framework:** Perform a final, comprehensive end-to-end test of the new orchestrator in a production-like environment.
        *   **Test Scripts:** This will involve running a master test suite that calls the individual manager test suites, ensuring the entire workflow is validated using our existing `test_runner.sh` and `hypervisor_test_runner.sh`.