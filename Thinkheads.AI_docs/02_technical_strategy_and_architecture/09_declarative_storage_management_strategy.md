---
title: Declarative Storage Management Strategy
summary: A strategy for safely managing ZFS pools and Proxmox storage in a declarative, automated environment.
document_type: Technical Strategy
status: Approved
version: 1.1.0
author: Roo
owner: Technical VP
tags:
  - Storage Management
  - ZFS
  - Proxmox
  - Declarative Configuration
  - Data Safety
review_cadence: Annual
last_reviewed: 2025-09-30
---

# Declarative Storage Management Strategy

**Version:** 1.1
**Date:** 2025-09-30
**Author:** Roo, Architect

---

## 1. High-Level Overview for Leadership

### 1.1. The Problem: The Risk of Automated Data Loss

The `--setup-hypervisor` feature, specifically the `hypervisor_feature_setup_zfs.sh` script, currently uses a "convergent" model for managing ZFS pools and Proxmox storage. This means the script attempts to make the live system's configuration match the declarative state defined in `phoenix_hypervisor_config.json`.

While effective for initial setup, this approach carries a significant risk in production environments. If a configuration file is changed—either intentionally or accidentally—the script may perform destructive operations like wiping disks or recreating ZFS pools to "correct" the perceived mismatch. This could lead to catastrophic data loss on a live system, as the script does not differentiate between a new setup and a pre-existing, data-filled one.

### 1.2. The Solution: Safety Over Unchecked Automation

This document outlines our **"state-validation" model**, which prioritizes data safety above all else.

**Our Guiding Principles:**

1.  **Default to Non-Destructive:** The script's default behavior will be to abort if it detects any change that could be destructive. It will never automatically delete or overwrite data.
2.  **Explicit User Consent:** Any destructive operation will require explicit user consent, either through an interactive prompt or a specific override flag in the configuration.
3.  **Clear Separation of Concerns:** The script's logic will be refactored to clearly distinguish between creating new resources and modifying existing ones.

### 1.3. Business Benefit: Increased Stability and Reduced Risk

By implementing this strategy, we will:

*   **Significantly reduce the risk of data loss,** enhancing the reliability of our hypervisor management tools.
*   **Increase operational stability** by preventing unintended, automated changes to production storage infrastructure.
*   **Build trust with our operations teams** by providing them with safer, more predictable tools.

---

## 2. Detailed Technical Plan for DevOps

### 2.1. Proposed Changes to Script Logic

The `hypervisor_feature_setup_zfs.sh` script incorporates state-validation logic to prevent accidental data loss.

#### 2.1.1. `create_zfs_pools` Function Modifications

1.  **Remove Forced Creation:** The `-f` (force) flag will be removed from the `zpool create` command.
2.  **State Validation:** Before attempting to create a pool, the script will check if a pool with the same name already exists.
    *   **If it exists:** The script will perform a detailed comparison of the existing pool's properties (RAID level, member disks) against the configuration file.
        *   If they match, the script will do nothing and log that the pool is already correctly configured.
        *   If they do not match, the script will abort with a detailed error message explaining the mismatch.
    *   **If it does not exist:** The script will proceed with creation, but only after verifying that the target disks are empty.
3.  **Safer Wiping:** The `wipefs -a` command will be preceded by a check to ensure the disk is not part of an active ZFS pool and does not contain any recognized filesystem signatures (unless a destructive mode is explicitly enabled).

#### 2.1.2. `add_proxmox_storage` Function Modifications

1.  **State Validation:** Before adding or modifying a Proxmox storage entry, the script will check the existing configuration.
2.  **Safe Updates Only:** The script will only perform "safe" updates, such as changing the `content` type. Any change to the underlying `pool` or `path` will be considered a destructive change and will cause the script to abort.

### 2.2. New Configuration Options and Execution Modes

To manage destructive operations, the script uses a `--mode` command-line flag and a configuration setting.

*   `--mode safe` (Default): The script will run in non-destructive mode. It will abort on any critical mismatch.
*   `--mode interactive`: The script will prompt the user for confirmation before performing any destructive action.
*   `--mode force-destructive`: The script will proceed with destructive actions without prompting. This mode should be used with extreme caution.

Additionally, a flag in `phoenix_hypervisor_config.json` can override the command-line mode:

```json
{
  "zfs": {
    "settings": {
      "allow_destructive_operations": false
    },
    "pools": [
      ...
    ]
  }
}
```

### 2.3. User Interaction Workflow

The following Mermaid diagram illustrates the proposed decision-making process for the `create_zfs_pools` function when running in `interactive` mode.

```mermaid
graph TD
    A[Start: create_zfs_pools] --> B{Pool Exists?};
    B -->|No| C{Disks Empty?};
    B -->|Yes| D{Config Matches?};
    C -->|Yes| E[Create Pool];
    C -->|No| F{Prompt: Wipe Disks?};
    F -->|Yes| G[Wipe Disks];
    G --> E;
    F -->|No| H[Abort];
    D -->|Yes| I[Log 'Already Configured'];
    D -->|No| J{Prompt: Destroy and Recreate?};
    J -->|Yes| K[Destroy Pool];
    K --> E;
    J -->|No| H;
    E --> L[End];
    I --> L;
    H --> L;