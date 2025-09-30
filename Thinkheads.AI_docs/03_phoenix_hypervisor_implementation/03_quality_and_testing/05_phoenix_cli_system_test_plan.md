---
title: Phoenix CLI End-to-End System Test Plan
summary: A comprehensive test plan for the phoenix CLI, covering all major functionalities from command parsing to full environment deployment. This document outlines the strategy, architecture, design, goals, requirements, and specifications for each testing stage.
document_type: Test Plan
status: In Progress
version: 1.0.0
author: Roo
owner: Project Manager
review_cadence: Ad-Hoc
---

# Phoenix CLI End-to-End System Test Plan

## 1. Introduction

This document outlines the comprehensive end-to-end system test plan for the `phoenix` Command Line Interface (CLI), the central orchestration tool for the Phoenix Hypervisor project. The successful completion of this test plan will validate the CLI's readiness for production use and ensure it aligns with our core architectural principles of strength, clear goals, and tight execution.

### 1.1. Strategic Importance

The `phoenix` CLI is the cornerstone of the Phoenix Hypervisor's automation strategy. It provides a single, unified interface for managing the entire lifecycle of the hypervisor, LXC containers, and VMs. A thoroughly tested and validated CLI is critical for ensuring the stability, reliability, and predictability of our virtualized infrastructure.

### 1.2. Architectural Principles Under Test

This test plan is designed to validate the following key architectural principles embodied in the `phoenix` CLI:

*   **Declarative Configuration:** The CLI's behavior is driven by a set of JSON configuration files. All tests will be executed against a controlled set of configuration files to ensure the CLI correctly interprets the desired state.
*   **Idempotency:** The CLI is designed to be idempotent, meaning it can be run multiple times without changing the result beyond the initial application. This will be a core focus of the testing process.
*   **Dispatcher-Manager Architecture:** The `phoenix` script acts as a dispatcher, routing commands to specialized manager scripts. The tests will validate this routing logic and the correct functioning of each manager.
*   **Dependency Resolution:** The CLI can resolve complex dependencies between guests. This will be tested with a dedicated scenario involving a mixed-resource dependency graph.

## 2. Test Stages

### 2.1. Stage 1: CLI Command & Argument Parsing

*   **Goal:** To verify that the `phoenix` CLI's dispatcher correctly parses all valid commands and arguments, and gracefully handles invalid inputs.
*   **Requirements:**
    *   The CLI must accept all documented verbs: `setup`, `create`, `delete`, `start`, `stop`, `restart`, `status`, and `LetsGo`.
    *   The CLI must correctly identify and route commands with and without target IDs.
    *   The CLI must provide a helpful usage message when invoked with `--help` or with invalid arguments.
*   **Specifications:**
    *   **Test Case 1.1 (Valid Commands):** Execute each valid verb with a valid target ID (where applicable) and verify that the command is routed to the correct manager script (as indicated by the log output).
    *   **Test Case 1.2 (Invalid Command):** Execute `phoenix invalid_command` and verify that the script exits with a non-zero status code and displays the usage message.
    *   **Test Case 1.3 (Missing Target):** Execute a command that requires a target (e.g., `phoenix create`) without a target ID and verify that the script exits with a non-zero status code and displays an appropriate error message.
    *   **Test Case 1.4 (Help Flag):** Execute `phoenix --help` and verify that the full usage message is displayed.

### 2.2. Stage 2: Hypervisor Setup (`phoenix setup`)

*   **Goal:** To ensure the `phoenix setup` command correctly initializes the hypervisor environment as defined in `phoenix_hypervisor_config.json`.
*   **Requirements:**
    *   The command must execute all setup scripts in the correct order as defined in `hypervisor-manager.sh`.
    *   The command must correctly configure ZFS pools, network interfaces, and other system-level settings.
*   **Specifications:**
    *   **Test Case 2.1 (Initial Setup):** On a clean Proxmox installation, execute `phoenix setup` and verify that all setup scripts are executed successfully. This will be validated by checking for the creation of ZFS pools, the presence of network configuration files, and the creation of specified users.
    *   **Test Case 2.2 (Idempotent Setup):** Re-run `phoenix setup` on an already configured hypervisor and verify that the command completes successfully without making any unintended changes.

### 2.3. Stage 3: LXC Container Lifecycle Management

*   **Goal:** To validate the full lifecycle management (create, start, stop, restart, delete) of LXC containers.
*   **Requirements:**
    *   The CLI must be able to create LXC containers from both templates and by cloning existing containers.
    *   All lifecycle commands must correctly interact with the Proxmox `pct` command.
*   **Specifications:**
    *   **Test Case 3.1 (Create from Template):** Create a new LXC container from a template and verify that the container is created with the correct configuration (hostname, memory, cores, network settings).
    *   **Test Case 3.2 (Clone Container):** Create a new LXC container by cloning an existing one and verify that the clone is successful and the new container has the correct configuration.
    *   **Test Case 3.3 (Start/Stop/Restart):** Execute the `start`, `stop`, and `restart` commands on a running container and verify the container's state changes accordingly using `pct status`.
    *   **Test Case 3.4 (Delete):** Execute the `delete` command on a container and verify that the container is successfully removed from the system.

### 2.4. Stage 4: VM Lifecycle Management

*   **Goal:** To validate the full lifecycle management of VMs.
*   **Requirements:**
    *   The CLI must be able to create VMs from templates and by cloning existing VMs.
    *   All lifecycle commands must correctly interact with the Proxmox `qm` command.
*   **Specifications:**
    *   **Test Case 4.1 (Create from Template):** Create a new VM from a template and verify its configuration.
    *   **Test Case 4.2 (Clone VM):** Create a new VM by cloning an existing one and verify the result.
    *   **Test Case 4.3 (Start/Stop/Restart):** Test the `start`, `stop`, and `restart` commands on a running VM and verify its state using `qm status`.
    *   **Test Case 4.4 (Delete):** Delete a VM and verify its removal.

### 2.5. Stage 5: Dependency Resolution

*   **Goal:** To verify that the CLI's dependency resolution logic correctly orders operations for a mixed list of LXC and VM targets.
*   **Requirements:**
    *   The CLI must correctly parse the `dependencies` and `clone_from_ctid`/`clone_from_vmid` fields in the configuration files.
    *   The CLI must perform a topological sort of the dependency graph to determine the correct execution order.
*   **Specifications:**
    *   **Test Case 5.1 (Mixed Dependency Graph):** Create a test configuration with a mix of LXC containers and VMs with interdependencies (e.g., a container that depends on a VM, and another container that depends on the first one). Execute a `create` command for all guests and verify from the log output that the operations are performed in the correct order.

### 2.6. Stage 6: LXC Feature Installation

*   **Goal:** To validate that all LXC feature installation scripts execute correctly and produce the expected outcome.
*   **Requirements:**
    *   Each feature script must be idempotent.
    *   Each feature script must correctly install and configure the specified software.
*   **Specifications:**
    *   For each feature (`base_setup`, `docker`, `nvidia`, `ollama`, `portainer`, `python_api_service`, `vllm`):
        *   **Test Case 6.X.1 (Initial Installation):** Create a new container with the feature and verify that the software is installed and configured correctly.
        *   **Test Case 6.X.2 (Idempotent Installation):** Re-run the `create` command for the same container and verify that the feature script runs without errors and does not make any unintended changes.

### 2.7. Stage 7: VM Feature Installation

*   **Goal:** To validate the VM feature installation scripts.
*   **Requirements:**
    *   The `docker` feature script must correctly install Docker in a VM.
*   **Specifications:**
    *   **Test Case 7.1.1 (Docker Installation):** Create a new VM with the `docker` feature and verify that Docker is installed and the specified user is added to the `docker` group.
    *   **Test Case 7.1.2 (Idempotent Installation):** Re-run the `create` command and verify the idempotency of the feature installation.

### 2.8. Stage 8: `LetsGo` Command

*   **Goal:** To validate the `phoenix LetsGo` command, which brings up the entire environment.
*   **Requirements:**
    *   The command must create all guests in the correct dependency order.
    *   The command must start all guests in the correct boot order.
*   **Specifications:**
    *   **Test Case 8.1 (Full Environment Deployment):** With a comprehensive configuration file defining multiple interdependent LXC containers and VMs, execute `phoenix LetsGo` and verify that all guests are created and started in the correct order.

### 2.9. Stage 9: Idempotency of All Operations

*   **Goal:** To formally verify the idempotency of all major CLI operations.
*   **Requirements:**
    *   Re-running any command should not result in an error or an unintended change to the system's state.
*   **Specifications:**
    *   **Test Case 9.1 (Lifecycle Commands):** After successfully creating and starting a guest, re-run the `create` and `start` commands for that guest and verify that the CLI reports that the guest is already in the desired state.
    *   **Test Case 9.2 (Setup Command):** Re-run the `phoenix setup` command on a fully configured hypervisor and verify that no changes are made.
    *   **Test Case 9.3 (LetsGo Command):** Re-run the `phoenix LetsGo` command on a fully deployed environment and verify that no changes are made.

### 2.10. Stage 10: Error Handling & Edge Cases

*   **Goal:** To ensure the CLI handles errors and edge cases gracefully.
*   **Requirements:**
    *   The CLI must provide clear, informative error messages.
    *   The CLI must exit with a non-zero status code on error.
*   **Specifications:**
    *   **Test Case 10.1 (Invalid Configuration):** Introduce errors into the JSON configuration files (e.g., a missing required field, an invalid path) and verify that the CLI detects the error and exits gracefully.
    *   **Test Case 10.2 (Missing Dependencies):** Attempt to create a guest whose dependencies are not met and verify that the CLI reports the missing dependency and fails.
    *   **Test Case 10.3 (Circular Dependencies):** Create a configuration with a circular dependency and verify that the CLI detects the cycle and exits with an appropriate error message.

## 3. Test Execution and Reporting

The test plan will be executed by a dedicated testing team. All test results will be recorded in a test report, which will include the following for each test case:

*   Test Case ID
*   Description
*   Execution Steps
*   Expected Result
*   Actual Result
*   Pass/Fail Status
*   Any relevant logs or screenshots

Upon completion of all test stages, a final test report will be generated and submitted for review.