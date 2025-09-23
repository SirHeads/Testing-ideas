---
title: Script Guide - phoenix_orchestrator.sh
summary: This document provides a comprehensive guide to the phoenix_orchestrator.sh script, detailing its purpose, usage, and the functions it provides for orchestrating LXC containers and VMs.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Script Guide
- Orchestrator
- LXC
- VM
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Script Guide: `phoenix_orchestrator.sh`

## 1. Introduction

This guide provides detailed documentation for the `phoenix_orchestrator.sh` script. This script is the central orchestration engine for the Phoenix Hypervisor environment. It is responsible for the entire lifecycle management of both LXC containers and QEMU/KVM virtual machines (VMs). It handles creation, configuration, starting, stopping, and deletion of guests, as well as the initial setup of the hypervisor itself. The script is designed to be idempotent and resumable, ensuring that operations can be run multiple times without adverse effects.

## 2. Purpose

The primary purpose of this script is to provide a single, unified interface for managing all aspects of the Phoenix Hypervisor. It automates complex provisioning and configuration tasks, enforces consistency through configuration files, and simplifies the management of a multi-guest environment.

## 3. Usage

The script supports several modes of operation, determined by command-line flags.

### Syntax

**LXC Container Orchestration:**
```bash
/usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh <CTID>... [--dry-run]
```

**Hypervisor Setup:**
```bash
/usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh --setup-hypervisor [--dry-run]
```

**VM Management:**
```bash
# Create a VM
/usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh --create-vm <vm_name> [--dry-run]

# Start a VM
/usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh --start-vm <vm_id> [--dry-run]

# Stop a VM
/usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh --stop-vm <vm_id> [--dry-run]

# Delete a VM
/usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh --delete-vm <vm_id> [--dry-run]
```

### Arguments

*   `<CTID>`: One or more numeric IDs of the LXC containers to orchestrate.
*   `--setup-hypervisor`: A flag to run the initial hypervisor setup and configuration scripts.
*   `--create-vm <vm_name>`: Creates a new VM with the specified name, based on definitions in the configuration file.
*   `--start-vm <vm_id>`: Starts the VM with the specified ID.
*   `--stop-vm <vm_id>`: Stops the VM with the specified ID.
*   `--delete-vm <vm_id>`: Deletes the VM with the specified ID.
*   `--dry-run`: An optional flag that simulates the execution of commands without making any actual changes to the system.

## 4. Script Breakdown

### Input and Configuration

The script's behavior is driven by command-line arguments and two main JSON configuration files:

*   **`/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json`**: Contains global settings for the hypervisor, including VM definitions, default VM parameters, and shared volume configurations.
*   **`/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`**: Contains detailed configurations for each LXC container, identified by its CTID. This includes settings for resources, networking, features, and application scripts.

### Core Functions

#### `parse_arguments()`

*   **Description**: Parses command-line arguments to determine the script's mode of operation (LXC, VM, or hypervisor setup) and validates the provided arguments.

#### `validate_inputs(CTID)`

*   **Description**: For LXC orchestration, this function validates that the `phoenix_lxc_configs.json` file exists and contains a valid configuration for the specified CTID.

#### `orchestrate_container_stateless(CTID)`

*   **Description**: This is the main function for orchestrating a single LXC container. It's a stateless orchestrator that ensures the container reaches its desired state based on the configuration.
*   **Orchestration Steps**:
    1.  `ensure_dependencies_running`: Checks for and orchestrates any dependent containers.
    2.  `ensure_container_defined`: Creates the container from a template or clone if it doesn't exist.
    3.  `ensure_container_configured`: Applies configurations like memory, cores, and disk size.
    4.  `generate_idmap_cycle`: Performs a start/stop cycle to ensure user namespace mappings are applied for unprivileged containers.
    5.  `verify_idmap_exists`: Confirms that the idmap was successfully created.
    6.  `apply_shared_volumes`: Mounts shared storage volumes into the container.
    7.  `start_container`: Starts the container.
    8.  `apply_features`: Executes feature installation scripts (e.g., Docker, NVIDIA).
    9.  `run_application_script`: Executes the final application-specific setup script.
    10. `run_health_check`: Performs a health check if defined.
    11. `create_template_snapshot`: Creates a snapshot if the container is marked as a template.

#### `handle_hypervisor_setup_state()`

*   **Description**: Manages the initial setup of the Proxmox hypervisor. It validates the main configuration file and then executes a series of setup scripts in a predefined order.

#### VM Management Functions (`create_vm`, `start_vm`, `stop_vm`, `delete_vm`)

*   **Description**: These functions wrap the Proxmox `qm` command to provide a consistent interface for managing the lifecycle of virtual machines based on configurations in `phoenix_hypervisor_config.json`.

### Helper Functions

*   `run_pct_command`, `run_qm_command`: Wrapper functions that execute Proxmox `pct` and `qm` commands, adding logging and dry-run support.
*   `topological_sort`: Sorts the list of CTIDs based on their dependencies to ensure they are orchestrated in the correct order.
*   `check_dependencies`: Checks for and installs required command-line tools like `jq` and `ajv`.

## 5. Dependencies

*   **`phoenix_hypervisor_common_utils.sh`**: Must be sourced for common utility functions (logging, error handling, etc.).
*   **`jq`**: Required for parsing JSON configuration files.
*   **`ajv-cli`**: Required for validating JSON configuration files against their schemas.
*   **`pct` & `qm`**: The standard Proxmox command-line tools for managing LXC containers and VMs.

## 6. Error Handling

The script is built with robust error handling:

*   **Strict Mode**: Uses `set -e` and `set -o pipefail` to exit immediately if any command fails.
*   **Logging**: Provides detailed logging to both `stdout` and a log file (`/var/log/phoenix_hypervisor/orchestrator_*.log`).
*   **Validation**: Performs input and configuration validation before proceeding with any operations.
*   **Idempotency**: Most operations are designed to be idempotent, meaning they can be run multiple times with the same outcome.

## 7. Customization

The entire behavior of the orchestrator is customized through the JSON configuration files. To provision a new container or VM, or to change the configuration of an existing one, you only need to modify the relevant JSON file. No changes to the orchestrator script itself are required.