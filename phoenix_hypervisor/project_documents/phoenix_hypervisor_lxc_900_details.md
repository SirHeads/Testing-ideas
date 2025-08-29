# LXC Container 900 - BaseTemplate - Requirements & Details

## Overview

This document details the purpose, configuration, and setup process for LXC container `900`, named `BaseTemplate`. This container serves exclusively as the foundational layer within the Phoenix Hypervisor's snapshot-based template hierarchy. It is never intended to be used as a final, running application container. All other templates (`901`, `902`, `903`, `920`) and standard application containers will be created by cloning snapshots taken from this base.

## Core Purpose & Function

*   **Role:** Foundational Template.
*   **Primary Function:** Provide a minimal, standardized Ubuntu 24.04 environment that serves as the starting point for all other, more specialized templates and containers.
*   **Usage:** Exclusively used for cloning. A ZFS snapshot (`base-snapshot`) is created after its initial setup for other containers/templates to clone from.

## Configuration (`phoenix_lxc_configs.json`)

*   **CTID:** `900`
*   **Name:** `BaseTemplate`
*   **Template Source:** `/fastData/shared-iso/template/cache/ubuntu-24.04-standard_24.04-2_amd64.tar.zst`
*   **Resources:**
    *   **CPU Cores:** `2` (Minimal allocation, suitable for base OS)
    *   **Memory:** `2048` MB (2 GB RAM, sufficient for base OS and setup tools)
    *   **Storage Pool:** `lxc-disks`
    *   **Storage Size:** `32` GB (Small root filesystem, intended to be expanded by cloning containers as needed)
*   **Network Configuration:**
    *   **Interface:** `eth0`
    *   **Bridge:** `vmbr0`
    *   **IP Address (Placeholder):** `10.0.0.200/24` (This IP is for template consistency and will be changed upon cloning)
    *   **Gateway:** `10.0.0.1`
    *   **MAC Address (Placeholder):** `52:54:00:AA:BB:CC` (Will be changed upon cloning)
*   **LXC Features:** `` (Empty string, no special features enabled at this base level)
*   **Security & Privileges:**
    *   **Unprivileged:** `true` (Runs in unprivileged mode for base security)
*   **GPU Assignment:** `none` (No GPU dependencies at the base level)
*   **Portainer Role:** `none` (Not a Portainer component)
*   **Template Metadata (for Snapshot Hierarchy):**
    *   **`is_template`:** `true` (Identifies this configuration as a template)
    *   **`template_snapshot_name`:** `base-snapshot` (Name of the ZFS snapshot this template will produce)

## Specific Setup Script (`phoenix_hypervisor_setup_900.sh`) Requirements

The `phoenix_hypervisor_setup_900.sh` script is responsible for the final configuration of the `BaseTemplate` container *after* its initial creation (`pct create`) and before the `base-snapshot` is taken. Its core responsibilities are:

1.  **Basic OS Configuration:**
    *   Ensure the container is fully booted and ready for setup.
    *   Perform standard OS updates (`apt update && apt upgrade`).
    *   Install fundamental utility packages (e.g., `curl`, `wget`, `vim`, `nano`, `htop`, `jq`, `rsync`, `git`).
    *   Perform any basic OS hardening or configuration steps deemed necessary for *all* derived containers.
    *   Ensure the default user (likely `ubuntu`) is configured appropriately.

2.  **Finalize and Snapshot Creation:**
    *   Once the base OS and essential tools are installed and configured, the script's final step is to shut down the container.
    *   It then executes `pct snapshot create 900 base-snapshot` to create the ZFS snapshot that forms the basis for the entire template hierarchy.
    *   Finally, it restarts the container.

## Interaction with Phoenix Hypervisor System

*   **Creation:** `phoenix_establish_hypervisor.sh` will identify `900` as a template (`is_template: true`) and that it has no `clone_from_template_ctid`. It will therefore call the standard creation process (`phoenix_hypervisor_create_lxc.sh` or direct `pct create` logic) to instantiate it from the Ubuntu template.
*   **Setup:** After creation and initial boot, `phoenix_establish_hypervisor.sh` will execute `phoenix_hypervisor_setup_900.sh`.
*   **Consumption:** Other templates (`901`, `902`, etc.) have `clone_from_template_ctid: "900"` in their configuration. The orchestrator will use this to determine that they should be created by cloning `900`'s `base-snapshot`.
*   **Idempotency:** The setup script (`phoenix_hypervisor_setup_900.sh`) must be idempotent. If `base-snapshot` already exists, it should skip the OS setup steps and potentially just log that the template is already prepared.

## Key Characteristics Summary

*   **Minimal Base:** Provides only the core OS and essential tools.
*   **Secure:** Runs unprivileged by default.
*   **Generic Network:** Uses placeholder IP/MAC which are changed on clone.
*   **No GPU:** Ensures no base dependencies on GPU hardware.
*   **Template Only:** Never used as a final application container.
*   **Snapshot Source:** The origin of the `base-snapshot` ZFS snapshot for the entire system.