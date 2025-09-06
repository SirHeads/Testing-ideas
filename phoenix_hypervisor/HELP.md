---
title: Document Title
summary: A brief, one-to-two-sentence summary of the document's purpose and content.
document_type: Strategy | Technical | Business Case | Report
status: Draft | In Review | Approved | Archived
version: 1.0.0
author: Author Name
owner: Team/Individual Name
tags: []
review_cadence: Annual | Quarterly | Monthly | None
last_reviewed: YYYY-MM-DD
---
# Phoenix Hypervisor

## Overview

The Phoenix Hypervisor project provides a unified, configuration-driven solution for the end-to-end setup of a Proxmox hypervisor and the provisioning of LXC containers. The `phoenix_orchestrator.sh` script serves as the single entry point for all operations, streamlining the entire workflow from bare metal to a fully configured, containerized environment.

This project is designed to be:

-   **Idempotent**: Rerunning the scripts will not cause unintended side effects.
-   **Modular**: Functionality is broken down into discrete, reusable scripts.
-   **Configuration-Driven**: All settings are managed in `hypervisor_config.json`, providing a single source of truth.

## System Configuration

The entire hypervisor and container setup is defined in `etc/hypervisor_config.json`. This file controls everything from ZFS pool configuration to the features installed in each LXC container.

### Example `hypervisor_config.json`

```json
{
  "zfs_pools": {
    "Raptor-01": {
      "disk_ids": ["ata-WDC_WDS400T2B0A-00SM50_20338D800549", "ata-WDC_WDS400T2B0A-00SM50_20338D800631"]
    }
  },
  "zfs_datasets": {
    "Raptor-01/homelab-o1": {
      "mountpoint": "/homelab-o1",
      "properties": {
        "compression": "lz4"
      }
    }
  },
  "admin_user": {
    "username": "proxmox-admin",
    "ssh_public_key": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHb..."
  },
  "samba_shares": {
    "homelab-o1-share": {
      "path": "/homelab-o1",
      "guest_ok": "yes",
      "read_only": "no"
    }
  },
  "nfs_shares": {
    "/homelab-o1": {
      "clients": "192.168.1.0/24(rw,sync,no_subtree_check)"
    }
  }
}
```

## Usage

The `phoenix_orchestrator.sh` script is the primary entry point for all operations. It has two main modes: `--setup-hypervisor` and LXC container provisioning.

### Hypervisor Setup

To perform the initial setup of the Proxmox hypervisor, use the `--setup-hypervisor` flag. This will read the `hypervisor_config.json` and execute all the necessary setup modules.

```bash
cd /path/to/phoenix_hypervisor/bin
./phoenix_orchestrator.sh --setup-hypervisor
```

The script will perform the following actions:

1.  **Initial Setup**: Updates the system and installs required packages.
2.  **ZFS Configuration**: Creates ZFS pools and datasets.
3.  **Admin User Creation**: Creates a new administrative user with sudo privileges.
4.  **NVIDIA Driver Installation**: Installs the appropriate NVIDIA drivers for GPU passthrough.
5.  **Samba and NFS Setup**: Configures file shares.

### LXC Container Provisioning

To provision an LXC container, run the orchestrator with the Container ID (CTID) as the argument. The container's configuration will be read from `phoenix_lxc_configs.json`.

```bash
cd /path/to/phoenix_hypervisor/bin
./phoenix_orchestrator.sh 950
```

The orchestrator follows a state machine to ensure the container is provisioned correctly:

1.  **Creation/Cloning**: Creates or clones the container.
2.  **Configuration**: Applies memory, CPU, and network settings.
3.  **Feature Installation**: Installs features like Docker, NVIDIA drivers, and vLLM.
4.  **Application Script**: Executes any final, container-specific scripts.

For more details on the LXC provisioning architecture, see `project_documents/orchestrator_architecture.md`.

### VM Management

The `phoenix_orchestrator.sh` script also provides comprehensive VM management capabilities. These operations allow for the creation, control, and removal of virtual machines directly from the command line.

```bash
cd /path/to/phoenix_hypervisor/bin
./phoenix_orchestrator.sh --create-vm <VMID> --template <TEMPLATE_NAME> --storage <STORAGE_POOL> --cores <NUM_CORES> --memory <RAM_MB> --disk <DISK_GB>
./phoenix_orchestrator.sh --start-vm <VMID>
./phoenix_orchestrator.sh --stop-vm <VMID>
./phoenix_orchestrator.sh --delete-vm <VMID>
```

**Arguments:**

*   `--create-vm <VMID>`: Creates a new virtual machine with the specified VMID.
    *   `--template <TEMPLATE_NAME>`: (Required for create) Specifies the VM template to use.
    *   `--storage <STORAGE_POOL>`: (Required for create) Specifies the storage pool for the VM disk.
    *   `--cores <NUM_CORES>`: (Required for create) Sets the number of CPU cores for the VM.
    *   `--memory <RAM_MB>`: (Required for create) Sets the RAM in MB for the VM.
    *   `--disk <DISK_GB>`: (Required for create) Sets the disk size in GB for the VM.
*   `--start-vm <VMID>`: Starts the virtual machine with the specified VMID.
*   `--stop-vm <VMID>`: Stops the virtual machine with the specified VMID.
*   `--delete-vm <VMID>`: Deletes the virtual machine with the specified VMID.
