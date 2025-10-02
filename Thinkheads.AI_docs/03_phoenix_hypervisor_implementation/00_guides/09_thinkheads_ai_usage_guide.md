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

All VM definitions and default settings are managed in the `phoenix_vm_configs.json` file. For a comprehensive guide to all the available options, please refer to the **[Comprehensive Guide to VM Creation](vm_creation_guide.md)**.

## 3. Command-Line Usage

The `phoenix` CLI now accepts the following commands for VM management.

### 3.1. Create a VM

To create a new VM, use the `create` command, followed by the ID of the VM as defined in the configuration file.

**Example:**

```bash
phoenix create 8001
```

This command will read the VM's definition from the configuration file, clone the template, apply the hardware and network configurations, and then orchestrate the feature installation via a dedicated NFS share.

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

The VM creation process is automated and follows a predefined workflow to ensure consistency. For a detailed diagram and explanation of the workflow, please refer to the **[Comprehensive Guide to VM Creation](vm_creation_guide.md)**.
