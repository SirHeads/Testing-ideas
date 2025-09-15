---
title: Shared Volume Management in Phoenix Hypervisor
summary: This document outlines the architecture and implementation of the declarative shared volume management feature in the Phoenix Hypervisor project.
document_type: Technical
status: Approved
version: 1.0.0
author: Roo
owner: Phoenix Hypervisor Team
tags:
- Shared Volumes
- Storage
- Architecture
- Phoenix Hypervisor
review_cadence: Annual
last_reviewed: 2025-09-14
---

# Shared Volume Management in Phoenix Hypervisor

## 1. Introduction

This document outlines the architecture and implementation of the declarative shared volume management feature in the Phoenix Hypervisor project. This feature provides a centralized, declarative, and automated way to manage shared storage between the Proxmox host and LXC containers, ensuring data persistence and inter-container communication.

## 2. Architecture

The shared volume management feature is built on the following architectural principles:

*   **Declarative Configuration:** All shared volume definitions are stored in the `phoenix_hypervisor_config.json` file, providing a single source of truth for the entire storage infrastructure.
*   **Schema Validation:** The structure and allowed values for the shared volume definitions are enforced by the `phoenix_hypervisor_config.schema.json` file, preventing misconfigurations and ensuring data integrity.
*   **Idempotent Orchestration:** The `phoenix_orchestrator.sh` script is responsible for creating and mounting the shared volumes in an idempotent manner, meaning it can be run multiple times without causing errors or unintended side effects.

### 2.1. Configuration

The `shared_volumes` block in the `phoenix_hypervisor_config.json` file is the central point of configuration for this feature. It is a JSON object where each key represents a shared volume and the value is an object that defines the volume's properties.

**Example:**

```json
"shared_volumes": {
    "ssl_certs": {
        "host_path": "/quickOS-shared-prod-data/ssl",
        "mounts": {
            "953": "/etc/nginx/ssl",
            "910": "/certs"
        }
    }
}
```

**Properties:**

*   `host_path`: The absolute path to the shared directory on the Proxmox host. This path should correspond to a ZFS dataset that has been configured for sharing.
*   `mounts`: A JSON object where each key is a container ID (CTID) and the value is the absolute path to the mount point inside the container.

### 2.2. Orchestration

The `phoenix_orchestrator.sh` script has been enhanced to handle the `shared_volumes` block. It performs the following actions:

1.  **Parses the `shared_volumes` block:** The script reads the configuration to understand which volumes need to be created and mounted.
2.  **Creates shared directories:** The script checks if the `host_path` for each volume exists on the host. If it doesn't, it creates the directory.
3.  **Enforces Permissions:** The script sets the ownership of the shared directory to `nobody:nogroup` and applies a purpose-driven permission scheme based on the volume's name (e.g., `ssl_certs`, `portainer_data`). This ensures a secure and consistent environment.
4.  **Mounts shared volumes:** The script checks if the mount points for each container exist. If they don't, it creates them using the `pct set --mp` command.

## 3. Usage

To use the shared volume feature, simply add a new entry to the `shared_volumes` block in the `phoenix_hypervisor_config.json` file. The `phoenix_orchestrator.sh` script will automatically handle the rest.