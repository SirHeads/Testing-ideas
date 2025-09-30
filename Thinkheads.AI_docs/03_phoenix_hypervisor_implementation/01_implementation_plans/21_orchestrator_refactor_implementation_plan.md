---
title: Orchestrator Refactor Detailed Implementation Plan
summary: A detailed, step-by-step implementation plan for refactoring the phoenix_orchestrator.sh into a modular, unified CLI, including script requirements, structural changes, and guiding principles.
document_type: Implementation Plan
status: Ready for Review
version: 1.0.0
author: Roo
owner: Technical VP
tags:
  - Phoenix Hypervisor
  - Orchestration
  - Refactoring
  - Implementation
review_cadence: Ad-Hoc
last_reviewed: 2025-09-30
---

# Orchestrator Refactor: Detailed Implementation Plan

## 1. Introduction

This document provides the detailed, actionable requirements for implementing the approved `Unified CLI Refactoring Proposal`. It will serve as the primary technical guide for the development phase, ensuring that the refactoring is executed in a structured and principled manner.

Our core architectural principles remain paramount:
*   **Single Source of Truth:** All state is defined in the JSON configuration files. The scripts read this state; they do not define it.
*   **Idempotency:** Every script and function must be safely runnable multiple times. The system should converge to the desired state, regardless of its starting point.

## 2. New Directory & File Structure

The refactor will result in the following changes to the `usr/local/phoenix_hypervisor/bin/` directory.

### 2.1. New Files/Directories

| Path | Description |
| :--- | :--- |
| `bin/phoenix` | The new primary entry point and smart dispatcher. |
| `bin/managers/` | A new directory to house the specialized logic scripts. |
| `bin/managers/hypervisor-manager.sh` | Manages all hypervisor-level tasks (`setup`, `test`). |
| `bin/managers/lxc-manager.sh` | Manages all LXC container lifecycle events (`create`, `delete`, `start`, etc.). |
| `bin/managers/vm-manager.sh` | Manages all VM lifecycle events (`create`, `delete`, `start`, etc.). |

### 2.2. Modified Files

| Path | Description |
| :--- | :--- |
| `bin/phoenix_hypervisor_common_utils.sh` | Will be updated with new helper functions for the dispatcher, such as target type resolution. |

### 2.3. Retired Files

| Path | Description |
| :--- | :--- |
| `bin/phoenix_orchestrator.sh` | This script will be removed and its functionality fully replaced by the new `phoenix` dispatcher and manager scripts. |

## 3. Script Requirements & Modifications

This section contains the detailed requirements for each new and modified script.

### 3.1. `phoenix` (Dispatcher) Requirements

This script will be the primary entry point for all user interactions. It must be robust, user-friendly, and intelligent.

**Core Logic:**
1.  **Argument Parsing:**
    *   The script must parse the first argument as the primary `verb` (e.g., `create`, `start`, `setup`).
    *   All subsequent arguments will be treated as a list of `targets` (e.g., guest IDs).
    *   It must support a `--help` flag that provides a user-friendly usage guide.
    *   It must handle invalid verbs or a lack of targets gracefully with a clear error message.

2.  **Verb Routing:**
    *   A `case` statement will be used to route logic based on the `verb`.
    *   **Special Verbs:** `setup` and `LetsGo` will be handled as special cases.
        *   `setup`: Immediately calls `hypervisor-manager.sh setup` and exits.
        *   `LetsGo`: Gathers all guest IDs from all config files, then proceeds to the dependency resolution step.
    *   **Standard Verbs:** For all other verbs (`create`, `start`, `stop`, `delete`, `test`), the script will proceed to the target resolution and ordering logic.

3.  **Target Resolution & Ordering:**
    *   For a given list of target IDs, the script will:
        *   Build a complete list of all guest objects (LXC and VM) by reading the config files.
        *   Construct a dependency graph based on `clone_from_ctid` and `dependencies` properties.
        *   Perform a topological sort on the graph to produce an ordered list of actions. For the `start` verb, it will sort by the `boot_order` property instead.
    *   This logic should be encapsulated in a dedicated function, likely within `phoenix_hypervisor_common_utils.sh`.

4.  **Delegation:**
    *   The script will iterate through the **sorted** list of targets.
    *   For each target, it will determine its type (LXC or VM) by checking which config file it belongs to.
    *   It will then call the appropriate manager script, passing the original verb and the target ID as arguments (e.g., `lxc-manager.sh create 950`).
    *   The script must capture the exit code of each manager script call and exit immediately if a failure occurs.

**Specifications and Test Cases:**
| Specification ID | Requirement | Test Case | Expected Result |
| :--- | :--- | :--- | :--- |
| PHOENIX-DIS-01 | Should display help message | `phoenix --help` | Displays usage info and exits 0. |
| PHOENIX-DIS-02 | Should handle invalid verbs | `phoenix foobar` | Prints "Error: Invalid verb 'foobar'" and exits 1. |
| PHOENIX-DIS-03 | Should handle missing targets | `phoenix start` | Prints "Error: Verb 'start' requires at least one target ID" and exits 1. |
| PHOENIX-DIS-04 | Should correctly route `setup` verb | `phoenix setup` | `hypervisor-manager.sh` is called with "setup". |
| PHOENIX-DIS-05 | Should resolve LXC target type | `phoenix start 950` | `lxc-manager.sh` is called with "start 950". |
| PHOENIX-DIS-06 | Should resolve VM target type | `phoenix start 1000` | `vm-manager.sh` is called with "start 1000". |
| PHOENIX-DIS-07 | Should handle unknown target ID | `phoenix start 9999` | Prints "Error: Target ID '9999' not found" and exits 1. |
| PHOENIX-DIS-08 | Should correctly order dependencies for `create` | `phoenix create 950 900` | `lxc-manager.sh` is called for 900, then for 950. |
| PHOENIX-DIS-09 | Should correctly order by boot order for `start` | `phoenix start 953 950` | `lxc-manager.sh` is called for 953 (order 1), then for 950 (order 3). |
| PHOENIX-DIS-10 | Should handle `LetsGo` verb | `phoenix LetsGo` | All guests are created and started in the correct dependency and boot order. |

### 3.2. `hypervisor-manager.sh` Requirements

This script is responsible for all actions that target the Proxmox host itself. It will be a direct port of the existing hypervisor setup logic.

**Core Logic:**
1.  **Argument Parsing:**
    *   The script must accept a single `verb` as its first argument (e.g., `setup`, `test`).
    *   It must provide a clear error message if the verb is missing or invalid.

2.  **Verb Routing:**
    *   A `case` statement will route logic based on the `verb`.
    *   **`setup`:** This verb will trigger the main hypervisor setup workflow. It will execute the exact same sequence of `hypervisor_setup/*` scripts as the original `phoenix_orchestrator.sh`. This entire block of logic can be lifted and shifted directly.
    *   **`test`:** This verb will trigger the hypervisor test suite. It will call the `hypervisor_test_runner.sh` script, passing through any additional arguments (like `--suite`).

**Dependencies:**
*   This script will continue to source `phoenix_hypervisor_common_utils.sh`.
*   It will read from `phoenix_hypervisor_config.json` to get the necessary configuration for setup tasks.

**Idempotency:**
*   The idempotency of this workflow is inherited from the underlying setup scripts (e.g., `hypervisor_feature_setup_zfs.sh`), which are already designed to be safely re-runnable. This principle must be maintained.

**Specifications and Test Cases:**
| Specification ID | Requirement | Test Case | Expected Result |
| :--- | :--- | :--- | :--- |
| PHX-HM-01 | Should handle invalid verbs | `hypervisor-manager.sh foobar` | Prints "Error: Invalid verb 'foobar'" and exits 1. |
| PHX-HM-02 | Should execute the full setup workflow | `hypervisor-manager.sh setup` | All setup scripts in the predefined sequence are executed successfully. |
| PHX-HM-03 | Should execute the hypervisor test suite | `hypervisor-manager.sh test` | The `hypervisor_test_runner.sh` script is called and runs the default suite. |
| PHX-HM-04 | Should pass through test suite arguments | `hypervisor-manager.sh test --suite smoke` | The `hypervisor_test_runner.sh` script is called with the `--suite smoke` argument. |

### 3.3. `lxc-manager.sh` Requirements

This script will contain the core state machine for creating, configuring, and managing LXC containers. The functions for this script can be almost entirely lifted from the existing `phoenix_orchestrator.sh`.

**Core Logic:**
1.  **Argument Parsing:**
    *   The script must accept a `verb` (e.g., `create`, `start`) as its first argument and a `target` ID as its second argument.
    *   It must validate that both arguments are present and that the target ID is a valid number.

2.  **Verb Routing:**
    *   A `case` statement will route logic based on the `verb`.
    *   **`create`:** This verb will execute the full, idempotent creation state machine for the given target ID. This involves calling the sequence of functions: `ensure_container_defined`, `apply_configurations`, `ensure_container_disk_size`, `start_container`, `apply_features`, `run_application_script`, `run_health_check`, and `create_template_snapshot`. All of these functions should be moved directly from `phoenix_orchestrator.sh` into this script.
    *   **`delete`:** This verb will execute the logic for stopping and deleting a container.
    *   **`start` \| `stop` \| `restart`:** These verbs will call the corresponding `pct` commands for the given target ID.
    *   **`reconfigure`:** This verb will re-apply the `apply_configurations` and `apply_features` steps to a running container.
    *   **`test`:** This verb will call the `test_runner.sh` script for the given target ID.

**Dependencies:**
*   This script will source `phoenix_hypervisor_common_utils.sh`.
*   It will read from `phoenix_lxc_configs.json` to get all necessary configuration for the target container.

**Function Migration:**
*   The following functions (and their helpers) will be moved from `phoenix_orchestrator.sh` into `lxc-manager.sh`:
    *   `validate_inputs` (will be adapted for the new argument structure)
    *   `check_storage_pool_exists`
    *   `create_container_from_template`
    *   `clone_container`
    *   `apply_configurations`
    *   `ensure_container_defined`
    *   `apply_zfs_volumes`
    *   `apply_dedicated_volumes`
    *   `ensure_container_disk_size`
    *   `start_container`
    *   `apply_features`
    *   `run_application_script`
    *   `run_health_check`
    *   `create_template_snapshot`
    *   `apply_apparmor_profile`

**Specifications and Test Cases:**
| Specification ID | Requirement | Test Case | Expected Result |
| :--- | :--- | :--- | :--- |
| PHX-LXC-01 | Should handle missing verb/target | `lxc-manager.sh create` | Prints "Error: Missing target ID" and exits 1. |
| PHX-LXC-02 | Should execute full create workflow | `lxc-manager.sh create 950` | The full state machine is executed for CT 950, resulting in a fully configured and running container. |
| PHX-LXC-03 | Should be idempotent | `lxc-manager.sh create 950` (run a second time) | The script logs that the container already exists in the desired state and exits 0 without making changes. |
| PHX-LXC-04 | Should handle `start` verb | `lxc-manager.sh start 950` | `pct start 950` is executed. |
| PHX-LXC-05 | Should handle `stop` verb | `lxc-manager.sh stop 950` | `pct stop 950` is executed. |
| PHX-LXC-06 | Should handle `delete` verb | `lxc-manager.sh delete 950` | The container is stopped and then destroyed. |
| PHX-LXC-07 | Should handle `test` verb | `lxc-manager.sh test 950` | The `test_runner.sh` script is called with target ID 950. |

### 3.4. `vm-manager.sh` Requirements

This script will mirror the structure of the `lxc-manager.sh` but will be responsible for the VM creation and management lifecycle.

**Core Logic:**
1.  **Argument Parsing:**
    *   The script must accept a `verb` (e.g., `create`, `start`) as its first argument and a `target` ID as its second argument.
    *   It must validate that both arguments are present and that the target ID is a valid number.

2.  **Verb Routing:**
    *   A `case` statement will route logic based on the `verb`.
    *   **`create`:** This verb will execute the full, idempotent VM creation state machine. This involves calling the sequence of functions: `ensure_vm_defined`, `apply_vm_configurations`, `start_vm`, `wait_for_guest_agent`, `apply_vm_features`, and `create_vm_snapshot`. All of these functions should be moved directly from `phoenix_orchestrator.sh` into this script.
    *   **`delete`:** This verb will execute the logic for stopping and deleting a VM.
    *   **`start` \| `stop` \| `restart`:** These verbs will call the corresponding `qm` commands for the given target ID.

**Dependencies:**
*   This script will source `phoenix_hypervisor_common_utils.sh`.
*   It will read from `phoenix_vm_configs.json` to get all necessary configuration for the target VM.

**Function Migration:**
*   The following functions (and their helpers) will be moved from `phoenix_orchestrator.sh` into `vm-manager.sh`:
    *   `orchestrate_vm` (the main state machine)
    *   `ensure_vm_defined`
    *   `create_vm_from_template` (and its Cloud-Init logic)
    *   `clone_vm`
    *   `apply_vm_configurations`
    *   `start_vm`
    *   `wait_for_guest_agent`
    *   `apply_vm_features`
    *   `create_vm_snapshot`

**Specifications and Test Cases:**
| Specification ID | Requirement | Test Case | Expected Result |
| :--- | :--- | :--- | :--- |
| PHX-VM-01 | Should handle missing verb/target | `vm-manager.sh create` | Prints "Error: Missing target ID" and exits 1. |
| PHX-VM-02 | Should execute full create workflow | `vm-manager.sh create 1000` | The full state machine is executed for VM 1000, resulting in a fully configured and running VM. |
| PHX-VM-03 | Should be idempotent | `vm-manager.sh create 1000` (run a second time) | The script logs that the VM already exists in the desired state and exits 0 without making changes. |
| PHX-VM-04 | Should handle `start` verb | `vm-manager.sh start 1000` | `qm start 1000` is executed. |
| PHX-VM-05 | Should handle `stop` verb | `vm-manager.sh stop 1000` | `qm stop 1000` is executed. |
| PHX-VM-06 | Should handle `delete` verb | `vm-manager.sh delete 1000` | The VM is stopped and then destroyed. |

### 3.5. `phoenix_hypervisor_common_utils.sh` Modifications

This central utility script will be enhanced to support the new dispatcher and manager architecture.

**New Functions:**
1.  **`resolve_target_type <ID>`:**
    *   **Purpose:** This function will be the core of the dispatcher's "smart" logic.
    *   **Inputs:** A single guest ID.
    *   **Logic:**
        *   It will check for the existence of the ID as a key in `phoenix_lxc_configs.json`. If found, it will `echo "lxc"` and return 0.
        *   It will check for the existence of the ID in the `vms` array of `phoenix_vm_configs.json`. If found, it will `echo "vm"` and return 0.
        *   If the ID is not found in either file, it will `echo "unknown"` and return 1.
    *   **Usage:** The dispatcher will call this for each target ID to determine which manager to delegate to.

2.  **`build_dependency_graph <ID...>`:**
    *   **Purpose:** To construct a list of targets in the correct order for execution.
    *   **Inputs:** A list of one or more guest IDs.
    *   **Logic:**
        *   It will read all LXC and VM configurations.
        *   It will parse the `clone_from_ctid` and `dependencies` fields to build an internal representation of the dependency graph.
        *   It will perform a topological sort on this graph.
        *   It will `echo` the sorted list of IDs, one per line.
    *   **Usage:** The dispatcher will call this function for the `create` verb to ensure templates are built before their children.

3.  **`get_boot_order <ID...>`:**
    *   **Purpose:** To produce a list of targets sorted by their boot order.
    *   **Inputs:** A list of one or more guest IDs.
    *   **Logic:**
        *   For each ID, it will resolve its type (LXC or VM) and read its `boot_order` property from the appropriate config file.
        *   It will then output the list of IDs sorted numerically by this property.
    *   **Usage:** The dispatcher will call this function for the `start` verb.

**Modified Functions:**
*   The existing `jq_get_value` function may need to be adapted or supplemented with new helpers to handle the slightly different structure of the VM config (an array of objects) versus the LXC config (a dictionary).

**Specifications and Test Cases:**
| Specification ID | Requirement | Test Case | Expected Result |
| :--- | :--- | :--- | :--- |
| PHX-CU-01 | `resolve_target_type` should find LXC | `resolve_target_type 950` | Echos "lxc" and returns 0. |
| PHX-CU-02 | `resolve_target_type` should find VM | `resolve_target_type 1000` | Echos "vm" and returns 0. |
| PHX-CU-03 | `resolve_target_type` should handle unknown | `resolve_target_type 9999` | Echos "unknown" and returns 1. |
| PHX-CU-04 | `build_dependency_graph` should sort correctly | `build_dependency_graph 950 900` | Echos "900\n950". |
| PHX-CU-05 | `get_boot_order` should sort correctly | `get_boot_order 950 953` | Echos "953\n950". |

## 4. Guiding Principles Check

This section details the specific strategies to ensure our core principles are maintained throughout the refactor.

### 4.1. Idempotency Strategy

Idempotency means that an operation can be applied multiple times without changing the result beyond the initial application. This is critical for a reliable orchestration system.

**Implementation:**
*   **Check-Then-Act:** Every function that creates or modifies a resource must first check if the resource already exists in the desired state.
    *   **Example:** The `create_container_from_template` function in `lxc-manager.sh` will first call `pct status <ID>`. If the container exists, the function will log a message and exit successfully without taking any action.
    *   **Example:** The `apply_configurations` function will check the current memory allocation of a container before running `pct set <ID> --memory ...`. If the value is already correct, it will skip the command.
*   **State Machines:** The `create` verb in the `lxc-manager.sh` and `vm-manager.sh` scripts will continue to act as a state machine. When run, it will check the state of the guest at each step (defined, configured, running, features applied) and only perform the necessary actions to bring it to the final, desired state.
*   **Error Handling:** Scripts will use `set -euo pipefail` to ensure that they exit immediately on any error, preventing the system from being left in a partially configured state.

### 4.2. Single Source of Truth (SSoT) Strategy

The SSoT principle dictates that all configuration and desired state must reside in our JSON configuration files (`phoenix_hypervisor_config.json`, `phoenix_lxc_configs.json`, `phoenix_vm_configs.json`). The scripts are for execution logic only and must not contain any configurable values.

**Implementation:**
*   **No Hardcoded Values:** All variables (e.g., memory sizes, IP addresses, feature lists, script names) must be read directly from the JSON config files within the manager scripts. There will be zero hardcoded configuration values in the shell scripts.
*   **Configuration-Driven Logic:** The behavior of the scripts will be driven entirely by the contents of the configuration.
    *   **Example:** The `apply_features` function in `lxc-manager.sh` will read the `.features` array from the config. If the array is empty, the function does nothing. If it contains `["docker", "nvidia"]`, the function will execute the corresponding scripts. The function itself has no knowledge of which features exist.
*   **Centralized Reading:** The manager scripts (`lxc-manager.sh`, `vm-manager.sh`) will be responsible for reading their respective configuration files. The `phoenix` dispatcher's only configuration-reading responsibility is to determine the target's type for delegation. This prevents configuration-reading logic from being scattered across multiple files.