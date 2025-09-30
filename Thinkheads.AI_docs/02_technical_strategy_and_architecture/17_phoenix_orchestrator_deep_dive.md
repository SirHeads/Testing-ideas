---
title: Phoenix CLI Deep Dive
summary: A detailed examination of the phoenix CLI, covering its strategic importance, architectural principles, and core functionalities.
document_type: Technical Deep Dive
status: In Progress
version: 2.0.0
author: Roo
owner: Technical VP
tags:
  - Phoenix CLI
  - Architecture
  - Automation
  - LXC
  - VM
review_cadence: Quarterly
last_reviewed: 2025-09-30
---

# Phoenix CLI Deep Dive

## 1. Strategic Importance

The `phoenix` CLI is the cornerstone of the Phoenix Hypervisor's automation strategy. It serves as the single point of entry for all provisioning, management, and testing tasks, ensuring a consistent, repeatable, and idempotent process. Its strategic importance cannot be overstated, as it embodies our core architectural principles—strength, clear goals, and tight execution—and enables the efficient management of a complex, multi-layered virtualized environment.

## 2. Architectural Principles

The CLI is designed around several key architectural principles that ensure its robustness, flexibility, and maintainability:

*   **Declarative Configuration:** The CLI is driven by a set of JSON configuration files (`phoenix_hypervisor_config.json`, `phoenix_lxc_configs.json`, `phoenix_vm_configs.json`), which serve as the single source of truth for the desired state of the system. This decouples the configuration from the execution logic, making the system more flexible and maintainable.
*   **Idempotency:** The CLI is designed to be idempotent, meaning it can be run multiple times without changing the result beyond the initial application. This is achieved by checking the current state of the system at each step and only performing the actions necessary to reach the desired state.
*   **Modularity (Dispatcher-Manager Architecture):** The `phoenix` CLI acts as a dispatcher, routing commands to specialized manager scripts (`hypervisor-manager.sh`, `lxc-manager.sh`, `vm-manager.sh`). This makes the system easy to extend and maintain, as new features can be added by modifying a specific manager without affecting the entire system.
*   **Statelessness:** The orchestrator is stateless, meaning it does not rely on any persistent state between runs. This makes the system more resilient to failures and allows it to be run in a variety of environments.

### 2.1. State Machine Implementation

Each manager script implements a sophisticated state machine for its domain (hypervisor, LXC, VM), ensuring that each step of the process is executed in the correct order and that the system can recover from failures. This includes robust error handling and retry logic for critical operations.

## 3. CLI Commands

The `phoenix` CLI provides a verb-first command structure to control its behavior:

| Command | Description |
| :--- | :--- |
| `phoenix setup` | Triggers the initial setup of the Proxmox hypervisor. |
| `phoenix create <ID>` | Creates the specified LXC container or VM. |
| `phoenix delete <ID>` | Deletes the specified LXC container or VM. |
| `phoenix start <ID>` | Starts the specified LXC container or VM. |
| `phoenix stop <ID>` | Stops the specified LXC container or VM. |
| `phoenix restart <ID>` | Restarts the specified LXC container or VM. |
| `phoenix reconfigure <ID>` | Forces the reconfiguration of an existing container or VM. |
| `phoenix test <SUITE>` | Runs a specific test suite against a container or the hypervisor. |
| `phoenix LetsGo` | Brings up the entire environment based on the configuration. |

## 4. Core Functionalities

### 4.1. Hypervisor Setup

The `phoenix setup` command triggers a series of scripts that perform the initial setup of the Proxmox hypervisor. This includes:

*   **Initial System Configuration:** Updating the system and installing required packages.
*   **ZFS Configuration:** Creating ZFS pools and datasets based on the declarative configuration in `phoenix_hypervisor_config.json`.
*   **User Management:** Creating administrative users with sudo privileges.
*   **NVIDIA Driver Installation:** Installing the appropriate NVIDIA drivers for GPU passthrough.
*   **File Sharing:** Configuring Samba and NFS for file sharing.
*   **AppArmor Setup:** Deploying and configuring custom AppArmor profiles to enhance security.

### 4.2. LXC Container Management

The `lxc-manager.sh` script manages the entire lifecycle of LXC containers. The process is as follows:

1.  **Validation:** The script validates the container's configuration in `phoenix_lxc_configs.json`.
2.  **Creation/Cloning:** The container is either created from a template or cloned from an existing container, based on the configuration. This supports a multi-layered templating strategy.
3.  **Configuration:** The script applies the container's configuration, including memory, cores, network settings, and AppArmor profile.
4.  **Startup:** The container is started with robust retry logic.
5.  **Feature Application:** Any specified feature scripts are executed inside the container.
6.  **Application Script:** The final application script is executed.
7.  **Health Checks:** The script runs any defined health checks to verify the container's status.
8.  **Snapshots:** The script creates snapshots of the container for backup and templating purposes.

### 4.3. VM Management

The `vm-manager.sh` script supports the creation and management of virtual machines, leveraging a sophisticated Cloud-Init-based approach for configuration:

*   **VM-Specific Configuration:** VM configurations are defined in `phoenix_vm_configs.json`.
*   **Dynamic Cloud-Init Generation:** The orchestrator dynamically generates Cloud-Init user-data and network-config files from templates.
*   **Template Image Provisioning:** The orchestrator can download and provision cloud images.
*   **GPU Passthrough:** The orchestrator supports GPU passthrough for VMs.

## 5. Testing and Validation

The `phoenix test` command allows for post-deployment validation of containers and the hypervisor itself, executing test suites defined in the configuration files.

## 6. Snapshot Strategies

The orchestrator employs a multi-layered snapshot strategy to create a flexible and efficient templating system:

*   **`pre-configured`:** A snapshot taken after the initial configuration and feature application.
*   **`final-form`:** A snapshot taken after the application script has been successfully executed.
*   **Template Snapshots:** Custom-named snapshots that are used to create specialized templates.

## 7. Orchestration Workflow

```mermaid
graph TD
    A[Start] --> B{Phoenix Command?};
    B -->|setup| C[hypervisor-manager.sh];
    B -->|create, delete, etc.| D[Dispatcher routes to lxc-manager.sh or vm-manager.sh];
    C --> E[Execute Hypervisor Setup Scripts];
    D --> F{Resource Type?};
    F -->|LXC| G[lxc-manager.sh];
    F -->|VM| H[vm-manager.sh];
    G --> I[Execute LXC State Machine];
    H --> J[Execute VM State Machine];
    I --> K[End];
    J --> K;
    E --> K;