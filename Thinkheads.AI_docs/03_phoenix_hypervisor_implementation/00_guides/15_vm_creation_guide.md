---
title: "Comprehensive Guide to VM Creation"
summary: "A detailed guide to the enhanced VM creation workflow in the Phoenix Hypervisor, covering configuration, features, and advanced usage."
document_type: "Implementation Guide"
status: "Draft"
version: "3.0.0"
author: "Roo"
owner: "Developer"
tags:
  - "VM Creation"
  - "Phoenix Hypervisor"
  - "Guide"
  - "Virtualization"
review_cadence: "Annual"
---

# Comprehensive Guide to VM Creation

This document provides a comprehensive overview of the enhanced Virtual Machine (VM) creation and management workflow within the Phoenix Hypervisor ecosystem. It is intended for developers and system administrators who are responsible for provisioning and maintaining virtualized environments.

## 1. Introduction

The Phoenix Hypervisor's VM management system is designed to be declarative, idempotent, and modular, aligning with the core architectural principles of the project. This guide will walk you through the entire lifecycle of a VM, from its definition in the central configuration file to its deployment and customization.

## 2. The Declarative Configuration Files

The VM management system is driven by a set of declarative JSON files that define the desired state of the entire environment.

*   **`phoenix_vm_configs.json`**: This file is the heart of the VM management system. It defines the configuration for each VM, including its resources, features, and the Docker stacks it should run.
*   **`phoenix_stacks_config.json`**: This file provides a catalog of reusable Docker stacks. Each stack is defined by a name, a Git repository, and an optional list of environment variables.
*   **`phoenix_hypervisor_config.json`**: This file contains global settings for the hypervisor, including the `portainer_api` object, which is used to securely store the credentials for the Portainer API.

### 2.1. High-Level Structure

The file is composed of two main sections: `vm_defaults` and `virtual_machines`.

```json
{
  "vm_defaults": {
    "template_name": "ubuntu-22.04-cloud-template-v3",
    "os_type": "l26",
    "cpu_sockets": 1,
    "cpu_cores": 2,
    "memory_mb": 4096,
    "boot_disk_size_gb": 50,
    "boot_disk_storage": "local-zfs",
    "network_bridge": "vmbr0",
    "network_model": "virtio",
    "features": ["base_setup"]
  },
  "virtual_machines": [
    {
      "vm_id": 1000,
      "vm_name": "rumpledev",
      "description": "Development Environment",
      "tags": ["development", "web-server"],
      "features": ["base_setup", "docker"],
      "docker_stacks": ["portainer", "qdrant"]
    }
  ]
}
```

-   **`vm_defaults`**: This section defines the default settings that will be applied to all VMs. This is a powerful feature that allows you to establish a baseline configuration for your entire environment, reducing redundancy and ensuring consistency.
-   **`virtual_machines`**: This is an array of objects, where each object represents a single VM. The settings defined here will override the `vm_defaults`, allowing you to create customized configurations for each machine.

### 2.2. Configuration Options

The following table provides a detailed explanation of each configuration option available in both the `vm_defaults` and the individual VM definitions.

| Key | Type | Description | Default |
| :-- | :--- | :--- | :--- |
| `template_name` | String | The name of the Proxmox template to clone. | `ubuntu-22.04-cloud-template-v3` |
| `os_type` | String | The operating system type. `l26` is for modern Linux kernels. | `l26` |
| `cpu_sockets` | Integer | The number of CPU sockets to allocate to the VM. | `1` |
| `cpu_cores` | Integer | The number of CPU cores to allocate to the VM. | `2` |
| `memory_mb` | Integer | The amount of RAM in megabytes to allocate to the VM. | `4096` |
| `boot_disk_size_gb` | Integer | The size of the boot disk in gigabytes. | `50` |
| `boot_disk_storage` | String | The Proxmox storage pool to use for the boot disk. | `local-zfs` |
| `network_bridge` | String | The Proxmox network bridge to connect the VM to. | `vmbr0` |
| `network_model` | String | The model of the virtual network card. `virtio` is recommended for performance. | `virtio` |
| `features`| Array | A list of feature scripts to execute after the VM is created. | `[]` |
| `docker_stacks` | Array | A list of Docker stack names (from `phoenix_stacks_config.json`) to deploy to the VM. | `[]` |
| `vm_id` | Integer | A unique identifier for the VM. | **Required** |
| `vm_name` | String | A unique name for the VM. | **Required** |
| `description` | String | A brief description of the VM's purpose. | `""` |
| `tags` | Array | A list of tags for organizing and filtering VMs. | `[]` |

## 3. The VM Creation Workflow

The `phoenix-cli create <VM_ID>` command initiates a fully automated, declarative workflow for provisioning VMs and deploying Docker stacks.

```mermaid
graph TD
    subgraph "Infrastructure Layer"
        A[Start: phoenix-cli create <VM_ID>] --> B{Read Configs};
        B --> C{Clone or Create VM};
        C --> D[Apply Hardware Config];
        D --> E[Start VM & Wait for Guest Agent];
        E --> F[Wait for cloud-init to Finish];
        F --> G[Execute `docker` feature];
        G --> H[End: VM Ready for Environment Layer];
    end

    subgraph "Environment Layer (Triggered by `phoenix-cli sync portainer` or `LetsGo`)"
        I[Start: portainer-manager.sh sync all] --> J{Deploy Portainer Instances};
        J --> K[Wait for Portainer API];
        K --> L[Authenticate & Sync Environments];
        L --> M{For each stack in `docker_stacks`};
        M --> N[Deploy Stack via Portainer API];
        N --> O[End: Environment Synced];
    end

    style A fill:#f9f,stroke:#333,stroke-width:2px
    style B fill:#bbf,stroke:#333,stroke-width:2px
    style C fill:#ccf,stroke:#333,stroke-width:2px
    style D fill:#ffc,stroke:#333,stroke-width:2px
    style E fill:#cfc,stroke:#333,stroke-width:2px
    style F fill:#fcf,stroke:#333,stroke-width:2px
    style G fill:#cff,stroke:#333,stroke-width:2px
    style H fill:#fcc,stroke:#333,stroke-width:2px
    style I fill:#f9f,stroke:#333,stroke-width:2px
    style J fill:#bbf,stroke:#333,stroke-width:2px
    style K fill:#ccf,stroke:#333,stroke-width:2px
    style L fill:#ffc,stroke:#333,stroke-width:2px
    style M fill:#cfc,stroke:#333,stroke-width:2px
    style N fill:#fcf,stroke:#333,stroke-width:2px
    style O fill:#cff,stroke:#333,stroke-width:2px
```

### 3.1. Workflow Steps Explained

The VM creation process is now clearly separated into two layers:

#### Infrastructure Layer (Managed by `vm-manager.sh`)

1.  **Initiation**: A user executes the `phoenix-cli create <VM_ID>` command (or it's part of `LetsGo`).
2.  **Configuration Reading**: The `phoenix-cli` reads `phoenix_vm_configs.json`, `phoenix_stacks_config.json`, and `phoenix_hypervisor_config.json`.
3.  **Clone or Create**: The `vm-manager.sh` either clones a template or creates a new VM from a cloud image.
4.  **Hardware Configuration**: Hardware settings (CPU, memory, etc.) are applied via `qm` commands.
5.  **Boot and Wait**: The VM is started, and the orchestrator waits for the QEMU Guest Agent to become responsive.
6.  **Wait for cloud-init**: The script waits for the `cloud-init` process to fully complete inside the VM.
7.  **Docker Installation**: The `docker` feature is executed inside the VM to install and configure the Docker engine.
8.  **VM Ready**: At this point, the VM is a fully provisioned Docker host, ready for the Environment Layer.

#### Environment Layer (Managed by `portainer-manager.sh`)

This layer is triggered by `phoenix-cli sync portainer` (or automatically by `phoenix-cli LetsGo`) and operates on the already provisioned Docker hosts.

1.  **Deploy Portainer Instances**: The `portainer-manager.sh` deploys the Portainer server container (on VM 1001) and agent containers (on other Docker-enabled VMs).
2.  **Wait for Portainer API**: The `portainer-manager.sh` waits for the Portainer API on the server VM to become responsive.
3.  **Authenticate & Sync Environments**: It authenticates with the Portainer API and ensures that all agent VMs are registered as environments within Portainer.
4.  **Deploy/Update Stacks**: For each VM configured with `docker_stacks`, the `portainer-manager.sh` uses the Portainer API to deploy or update the specified Docker stacks to the corresponding Portainer environment.

## 4. Practical Example: A Declarative, Multi-Service Environment

This example demonstrates how to use the new declarative stack management system to deploy a multi-service application. We will create two VMs: one for Portainer and one for a Qdrant vector database.

### 4.1. The `phoenix_stacks_config.json` Configuration

First, we define our stacks in `phoenix_stacks_config.json`.

```json
{
  "docker_stacks": {
    "qdrant_service": {
      "description": "Qdrant vector database for RAG.",
      "compose_file_path": "persistent-storage/qdrant/docker-compose.yml",
      "environments": {
        "production": {
          "variables": [],
          "files": []
        }
      }
    },
    "thinkheads_ai_app": {
      "description": "The main Thinkheads.AI web application.",
      "compose_file_path": "persistent-storage/thinkheads_ai/docker-compose.yml",
      "environments": {
        "production": {
          "variables": [
            { "name": "DATABASE_USER", "value": "prod_user" },
            { "name": "DATABASE_PASS", "value": "PROD_SECRET_PASSWORD" },
            { "name": "API_PORT", "value": "8000" }
          ],
          "files": [
            {
              "source": "persistent-storage/thinkheads_ai/configs/prod.env",
              "destination_in_container": "/app/.env"
            }
          ]
        },
        "testing": {
          "variables": [
            { "name": "DATABASE_USER", "value": "test_user" },
            { "name": "DATABASE_PASS", "value": "TEST_SECRET_PASSWORD" },
            { "name": "API_PORT", "value": "8001" }
          ],
          "files": [
            {
              "source": "persistent-storage/thinkheads_ai/configs/test.env",
              "destination_in_container": "/app/.env"
            }
          ]
        },
        "development": {
          "variables": [
            { "name": "DATABASE_USER", "value": "dev_user" },
            { "name": "DATABASE_PASS", "value": "DEV_SECRET_PASSWORD" },
            { "name": "API_PORT", "value": "8002" }
          ],
          "files": [
            {
              "source": "persistent-storage/thinkheads_ai/configs/dev.env",
              "destination_in_container": "/app/.env"
            }
          ]
        }
      }
    }
  }
}
```

### 4.2. The `phoenix_vm_configs.json` Configuration

Next, we define our VMs and assign the stacks to them.

```json
{
  "vm_defaults": {
    "template_name": "ubuntu-22.04-cloud-template-v3",
    "features": ["base_setup", "docker"]
  },
  "virtual_machines": [
    {
      "vm_id": 1001,
      "vm_name": "portainer",
      "docker_stacks": [
        { "name": "portainer", "environment": "production" }
      ]
    },
    {
      "vm_id": 1002,
      "vm_name": "qdrant-db",
      "docker_stacks": [
        { "name": "qdrant_service", "environment": "production" },
        { "name": "thinkheads_ai_app", "environment": "development" }
      ]
    }
  ]
}
```

### 4.3. Creating the VMs

To create these VMs and deploy the stacks, you would execute:

```bash
# First, create the VMs (Infrastructure Layer)
phoenix-cli create 1001
phoenix-cli create 1002

# Then, synchronize the Portainer environment and deploy stacks (Environment Layer)
phoenix-cli sync portainer
```

Alternatively, to perform a full setup from scratch, you would use the `LetsGo` command:

```bash
phoenix-cli LetsGo
```

The `phoenix-cli` will first create the VMs and install Docker. Then, the `portainer-manager.sh` will deploy the Portainer server and agents, and use the Portainer API to deploy the Portainer and Qdrant stacks. The result is a fully configured, multi-service environment, provisioned from declarative commands.

For granular control, you can also synchronize a specific stack to a specific VM:

```bash
phoenix-cli sync stack qdrant_service to 1002
