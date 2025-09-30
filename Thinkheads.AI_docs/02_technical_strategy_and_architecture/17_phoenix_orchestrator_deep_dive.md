---
title: Phoenix Orchestrator Deep Dive
summary: A detailed examination of the phoenix_orchestrator.sh script, covering its strategic importance, architectural principles, and core functionalities.
document_type: Technical Deep Dive
status: In Progress
version: 1.1.0
author: Roo
owner: Technical VP
tags:
  - Phoenix Orchestrator
  - Architecture
  - Automation
  - LXC
  - VM
review_cadence: Quarterly
last_reviewed: 2025-09-30
---

# Phoenix Orchestrator Deep Dive

## 1. Strategic Importance

The `phoenix_orchestrator.sh` script is the cornerstone of the Phoenix Hypervisor's automation strategy. It serves as the single point of entry for all provisioning, management, and testing tasks, ensuring a consistent, repeatable, and idempotent process. Its strategic importance cannot be overstated, as it embodies our core architectural principles—strength, clear goals, and tight execution—and enables the efficient management of a complex, multi-layered virtualized environment.

## 2. Architectural Principles

The orchestrator is designed around several key architectural principles that ensure its robustness, flexibility, and maintainability:

*   **Declarative Configuration:** The script is driven by a set of JSON configuration files (`phoenix_hypervisor_config.json`, `phoenix_lxc_configs.json`, `phoenix_vm_configs.json`), which serve as the single source of truth for the desired state of the system. This decouples the configuration from the execution logic, making the system more flexible and maintainable.
*   **Idempotency:** The orchestrator is designed to be idempotent, meaning it can be run multiple times without changing the result beyond the initial application. This is achieved by checking the current state of the system at each step and only performing the actions necessary to reach the desired state.
*   **Modularity:** The orchestrator is composed of a series of modular, single-purpose scripts that are called in a specific order. This makes the system easy to extend and maintain, as new features can be added by simply creating a new script and adding it to the orchestration workflow.
*   **Statelessness:** The orchestrator is stateless, meaning it does not rely on any persistent state between runs. This makes the system more resilient to failures and allows it to be run in a variety of environments.

### 2.1. State Machine Implementation

The script implements a sophisticated state machine for both LXC and VM provisioning, ensuring that each step of the process is executed in the correct order and that the system can recover from failures. This includes robust error handling and retry logic for critical operations like starting containers and VMs.

## 3. Orchestration Flags and Arguments

The `phoenix_orchestrator.sh` script provides a rich set of command-line flags and arguments to control its behavior:

| Flag/Argument | Description |
| :--- | :--- |
| `<ID>` | The ID of the LXC container or VM to orchestrate. |
| `--setup-hypervisor` | Triggers the initial setup of the Proxmox hypervisor. |
| `--delete <ID>` | Deletes the specified LXC container or VM. |
| `--dry-run` | Enables dry-run mode, which logs the commands that would be executed without actually running them. |
| `--reconfigure` | Forces the reconfiguration of an existing container or VM. |
| `--smoke-test` | Runs a series of smoke tests to verify the health of the hypervisor and its components. |
| `--test <SUITE>` | Runs a specific test suite against a container or the hypervisor. |
| `--wipe-disks` | **DANGEROUS:** Wipes the disks during hypervisor setup. Use with extreme caution. |

## 4. Core Functionalities

### 4.1. Hypervisor Setup

The `--setup-hypervisor` flag triggers a series of scripts that perform the initial setup of the Proxmox hypervisor. This includes:

*   **Initial System Configuration:** Updating the system and installing required packages.
*   **ZFS Configuration:** Creating ZFS pools and datasets based on the declarative configuration in `phoenix_hypervisor_config.json`.
*   **User Management:** Creating administrative users with sudo privileges.
*   **NVIDIA Driver Installation:** Installing the appropriate NVIDIA drivers for GPU passthrough.
*   **File Sharing:** Configuring Samba and NFS for file sharing.
*   **AppArmor Setup:** Deploying and configuring custom AppArmor profiles to enhance security.

### 4.2. LXC Container Creation

The orchestrator manages the entire lifecycle of LXC containers, from creation to deletion. The process is as follows:

1.  **Validation:** The script validates the container's configuration in `phoenix_lxc_configs.json`.
2.  **Creation/Cloning:** The container is either created from a template or cloned from an existing container, based on the configuration. This supports a multi-layered templating strategy, where base templates are progressively specialized with features like GPU support and Docker.
3.  **Configuration:** The script applies the container's configuration, including memory, cores, network settings, and AppArmor profile.
4.  **Startup:** The container is started with robust retry logic to handle transient startup issues.
5.  **Feature Application:** Any specified feature scripts (e.g., Docker, NVIDIA, vLLM) are executed inside the container.
6.  **Application Script:** The final application script is executed, using a contextual execution model where the script and its dependencies are copied into a temporary directory within the container.
7.  **Health Checks:** The script runs any defined health checks to verify the container's status.
8.  **Snapshots:** The script creates snapshots of the container for backup and templating purposes, supporting multiple snapshot strategies (`pre-configured`, `final-form`, and custom template snapshots).

### 4.3. VM Creation

The orchestrator also supports the creation and management of virtual machines, leveraging a sophisticated Cloud-Init-based approach for configuration:

*   **VM-Specific Configuration:** VM configurations are defined in `phoenix_vm_configs.json`.
*   **Dynamic Cloud-Init Generation:** The orchestrator dynamically generates Cloud-Init user-data and network-config files from templates, injecting values from the JSON configuration. This allows for highly customized, automated VM deployments.
*   **Template Image Provisioning:** The orchestrator can download and provision cloud images, creating a base template that can be cloned for subsequent VM deployments.
*   **GPU Passthrough:** The orchestrator supports GPU passthrough for VMs, allowing them to be used for compute-intensive tasks.

## 5. Testing and Validation

The orchestrator includes a built-in testing framework that allows for post-deployment validation of containers and the hypervisor itself. This is controlled by the `--test` and `--smoke-test` flags, which execute test suites defined in the configuration files. This ensures that all components are functioning correctly after deployment and helps to prevent regressions.

## 6. Snapshot Strategies

The orchestrator employs a multi-layered snapshot strategy to create a flexible and efficient templating system:

*   **`pre-configured`:** A snapshot taken after the initial configuration and feature application, but before the application script is run. This provides a clean, pre-configured base for creating new containers.
*   **`final-form`:** A snapshot taken after the application script has been successfully executed, representing the final, desired state of the container.
*   **Template Snapshots:** Custom-named snapshots that are used to create specialized templates (e.g., `Template-GPU`, `Template-Docker`).

## 7. Orchestration Workflow

```mermaid
graph TD
    A[Start] --> B{Orchestration Mode?};
    B -->|Hypervisor Setup| C[Execute Hypervisor Setup Scripts];
    B -->|LXC Orchestration| D[Validate LXC Config];
    B -->|VM Orchestration| E[Validate VM Config];
    D --> F{Exists?};
    F -->|No| G{Clone or Create?};
    G -->|Create| H[Create from Template];
    G -->|Clone| I[Clone from Snapshot];
    F -->|Yes| J[Apply Configurations];
    H --> J;
    I --> J;
    J --> K[Start Container];
    K --> L[Apply Features];
    L --> M[Run Application Script];
    M --> N[Run Health Checks];
    N --> O[Create Snapshots];
    O --> P[End];
    E --> Q{Exists?};
    Q -->|No| R{Clone or Create?};
    R -->|Create| S[Create from Image];
    R -->|Clone| T[Clone from Template];
    Q -->|Yes| U[Apply Configurations];
    S --> U;
    T --> U;
    U --> V[Generate Cloud-Init];
    V --> W[Start VM];
    W --> X[Wait for Guest Agent];
    X --> Y[Create Snapshot];
    Y --> P;
    C --> P;