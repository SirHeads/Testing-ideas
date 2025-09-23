---
title: 'Usage Guide: VM Management'
summary: This guide provides instructions on how to use the new Virtual Machine (VM) management features in the phoenix_orchestrator.sh script.
document_type: Guide
status: Approved
version: '1.0'
author: Roo
owner: Thinkheads.AI
tags:
  - phoenix_hypervisor
  - vm_management
  - usage_guide
review_cadence: Annual
last_reviewed: '2025-09-23'
---
# Usage Guide: VM Management

## 1. Introduction

This guide provides instructions on how to use the new Virtual Machine (VM) management features in the `phoenix_orchestrator.sh` script. These features are designed to simplify the creation and administration of the mirrored development environments for the "ThinkHeadsAI" project.

## 2. Configuration

All VM definitions and default settings are managed in the `phoenix_hypervisor_config.json` file.

### 2.1. VM Defaults

The `vm_defaults` section allows you to specify default values for VM properties. These defaults are used when a specific VM definition does not override them.

```json
"vm_defaults": {
    "template": "ubuntu-24.04-standard",
    "cores": 4,
    "memory_mb": 8192,
    "disk_size_gb": 100,
    "storage_pool": "local-lvm",
    "network_bridge": "vmbr0"
}
```

### 2.2. VM Definitions

The `vms` array contains a list of all the VMs to be managed by the orchestrator. Each object in the array defines a specific VM.

```json
"vms": [
    {
        "name": "webserver-vm",
        "cores": 4,
        "memory_mb": 8192,
        "disk_size_gb": 100,
        "post_create_scripts": [
            "install_webserver.sh"
        ]
    }
]
```

## 3. Command-Line Usage

The `phoenix_orchestrator.sh` script now accepts the following new arguments for VM management.

### 3.1. Create a VM

To create a new VM, use the `--create-vm` argument, followed by the name of the VM as defined in the configuration file.

**Example:**

```bash
./phoenix_orchestrator.sh --create-vm webserver-vm
```

This command will:
1.  Read the `webserver-vm` definition from the configuration file.
2.  Apply the default settings from `vm_defaults`.
3.  Create and configure the VM using a series of `qm` commands.
4.  Execute the `install_webserver.sh` script inside the newly created VM.

### 3.2. Start a VM

To start an existing VM, use the `--start-vm` argument, followed by the VM ID.

**Example:**

```bash
./phoenix_orchestrator.sh --start-vm 9002
```

### 3.3. Stop a VM

To stop a running VM, use the `--stop-vm` argument, followed by the VM ID.

**Example:**

```bash
./phoenix_orchestrator.sh --stop-vm 9002
```

### 3.4. Delete a VM

To delete a VM, use the `--delete-vm` argument, followed by the VM ID. This action is irreversible and will remove the VM and all its data.

**Example:**

```bash
./phoenix_orchestrator.sh --delete-vm 9002
```

## 4. VM Creation Workflow

The VM creation process is automated and follows a predefined workflow to ensure consistency.

```mermaid
graph TD
    A[Start: --create-vm] --> B{Parse Config};
    B --> C{Apply Defaults};
    C --> D[Create VM];
    D --> E[Set CPU and Memory];
    E --> F[Start VM];
    F --> G{Execute Post-Create Scripts};
    G --> H[End: VM Ready];
