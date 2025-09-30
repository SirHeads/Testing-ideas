---
title: 'Usage Guide: VM Management'
summary: This guide provides instructions on how to use the new Virtual Machine (VM) management features in the phoenix CLI.
document_type: Guide
status: Approved
version: '2.0'
author: Roo
owner: Thinkheads.AI
tags:
  - phoenix_hypervisor
  - vm_management
  - usage_guide
  - phoenix_cli
review_cadence: Annual
last_reviewed: '2025-09-30'
---
# Usage Guide: VM Management

## 1. Introduction

This guide provides instructions on how to use the new Virtual Machine (VM) management features in the `phoenix` CLI. These features are designed to simplify the creation and administration of the mirrored development environments for the "ThinkHeadsAI" project.

## 2. Configuration

All VM definitions and default settings are managed in the `phoenix_vm_configs.json` file.

### 2.1. VM Defaults

The `vm_defaults` section allows you to specify default values for VM properties. These defaults are used when a specific VM definition does not override them.

```json
"vm_defaults": {
    "template": "ubuntu-24.04-standard",
    "cores": 4,
    "memory_mb": 8192,
    "disk_size_gb": 100,
    "storage_pool": "quickOS-vm-disks",
    "network_bridge": "vmbr0"
}
```

### 2.2. VM Definitions

The `vms` array contains a list of all the VMs to be managed by the orchestrator. Each object in the array defines a specific VM.

```json
"vms": [
    {
        "vmid": 8001,
        "name": "docker-vm-01",
        "clone_from_vmid": 8000,
        "features": [
            "docker"
        ],
        "network_config": {
            "ip": "10.0.0.101/24",
            "gw": "10.0.0.1"
        }
    }
]
```

## 3. Command-Line Usage

The `phoenix` CLI now accepts the following commands for VM management.

### 3.1. Create a VM

To create a new VM, use the `create` command, followed by the ID of the VM as defined in the configuration file.

**Example:**

```bash
phoenix create 8001
```

This command will:
1.  Read the VM definition with `vmid` 8001 from the configuration file.
2.  Clone the VM from the specified `clone_from_vmid`.
3.  Apply the network and user configurations via Cloud-Init.
4.  Start the VM and wait for the QEMU guest agent to become responsive.
5.  Apply the specified features (e.g., "docker") via Cloud-Init.

### 3.2. Start a VM

To start an existing VM, use the `start` command, followed by the VM ID.

**Example:**

```bash
phoenix start 8001
```

### 3.3. Stop a VM

To stop a running VM, use the `stop` command, followed by the VM ID.

**Example:**

```bash
phoenix stop 8001
```

### 3.4. Delete a VM

To delete a VM, use the `delete` command, followed by the VM ID. This action is irreversible and will remove the VM and all its data.

**Example:**

```bash
phoenix delete 8001
```

## 4. VM Creation Workflow

The VM creation process is automated and follows a predefined workflow to ensure consistency.

```mermaid
graph TD
    A[Start: phoenix create <ID>] --> B{Parse Config};
    B --> C{Clone from Template};
    C --> D[Apply Cloud-Init Configs];
    D --> E[Start VM];
    E --> F{Wait for Guest Agent};
    F --> G{Apply Features};
    G --> H[End: VM Ready];
