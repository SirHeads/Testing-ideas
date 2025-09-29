---
title: Phoenix Orchestrator Deep Dive
summary: A detailed examination of the phoenix_orchestrator.sh script, covering its strategic importance, architectural principles, and core functionalities.
document_type: Technical Deep Dive
status: Draft
version: 1.0.0
author: Roo
owner: Technical VP
tags:
  - Phoenix Orchestrator
  - Architecture
  - Automation
review_cadence: Quarterly
last_reviewed: 2025-09-29
---

# Phoenix Orchestrator Deep Dive

## 1. Strategic Importance

The `phoenix_orchestrator.sh` script is the cornerstone of the Phoenix Hypervisor's automation strategy. It serves as the single point of entry for all provisioning and management tasks, ensuring a consistent, repeatable, and idempotent process. Its strategic importance cannot be overstated, as it embodies our core architectural principles and enables the efficient management of a complex, multi-container environment.

## 2. Architectural Principles

The orchestrator is designed around several key architectural principles:

*   **Declarative Configuration:** The script is driven by a set of JSON configuration files, which serve as the single source of truth for the desired state of the system. This decouples the configuration from the execution logic, making the system more flexible and maintainable.
*   **Idempotency:** The orchestrator is designed to be idempotent, meaning it can be run multiple times without changing the result beyond the initial application. This is achieved by checking the current state of the system at each step and only performing the actions necessary to reach the desired state.
*   **Modularity:** The orchestrator is composed of a series of modular, single-purpose scripts that are called in a specific order. This makes the system easy to extend and maintain, as new features can be added by simply creating a new script and adding it to the orchestration workflow.
*   **Statelessness:** The orchestrator is stateless, meaning it does not rely on any persistent state between runs. This makes the system more resilient to failures and allows it to be run in a variety of environments.

## 3. Core Functionalities

### 3.1. Hypervisor Setup

The `--setup-hypervisor` flag triggers a series of scripts that perform the initial setup of the Proxmox hypervisor. This includes:

*   **Initial System Configuration:** Updating the system and installing required packages.
*   **ZFS Configuration:** Creating ZFS pools and datasets.
*   **User Management:** Creating administrative users with sudo privileges.
*   **NVIDIA Driver Installation:** Installing the appropriate NVIDIA drivers for GPU passthrough.
*   **File Sharing:** Configuring Samba and NFS for file sharing.
*   **AppArmor Setup:** Deploying and configuring custom AppArmor profiles.

### 3.2. LXC Container Creation

The orchestrator manages the entire lifecycle of LXC containers, from creation to deletion. The process is as follows:

1.  **Validation:** The script validates the container's configuration in `phoenix_lxc_configs.json`.
2.  **Creation/Cloning:** The container is either created from a template or cloned from an existing container, based on the configuration.
3.  **Configuration:** The script applies the container's configuration, including memory, cores, network settings, and AppArmor profile.
4.  **Startup:** The container is started.
5.  **Feature Application:** Any specified feature scripts (e.g., Docker, NVIDIA) are executed inside the container.
6.  **Application Script:** The final application script is executed.
7.  **Health Checks:** The script runs any defined health checks to verify the container's status.
8.  **Snapshots:** The script creates snapshots of the container for backup and templating purposes.

### 3.3. VM Creation

The orchestrator also supports the creation and management of virtual machines. The process is similar to LXC container creation, with the following key differences:

*   **VM-Specific Configuration:** VM configurations are defined in `phoenix_vm_configs.json`.
*   **Cloud-Init:** The orchestrator uses Cloud-Init to perform the initial configuration of the VM, including setting the hostname, creating users, and installing packages.
*   **GPU Passthrough:** The orchestrator supports GPU passthrough for VMs, allowing them to be used for compute-intensive tasks.