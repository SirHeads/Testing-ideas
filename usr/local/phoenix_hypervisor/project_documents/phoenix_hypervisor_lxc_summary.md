---
title: Phoenix Hypervisor - LXC Container Summary
summary: This document provides a high-level summary of the LXC containers and templates
  defined in `phoenix_lxc_configs.json` for the Phoenix Hypervisor system, outlining
  their roles within the snapshot-based template hierarchy and their primary functions.
document_type: Strategy | Technical | Business Case | Report
status: Draft | In Review | Approved | Archived
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Team/Individual Name
tags:
- Phoenix Hypervisor
- LXC
- Container Summary
- Templates
- ZFS Snapshots
- Container Hierarchy
- Proxmox
review_cadence: Annual | Quarterly | Monthly | None
last_reviewed: YYYY-MM-DD
---
This document provides a high-level summary of the LXC containers and templates defined in `phoenix_lxc_configs.json` for the Phoenix Hypervisor system. It outlines their roles within the snapshot-based template hierarchy and their primary functions.

## Overview

This document provides a high-level summary of the LXC containers and templates defined in `phoenix_lxc_configs.json` for the Phoenix Hypervisor system. It outlines their roles within the snapshot-based template hierarchy and their primary functions.

## Container Hierarchy & Roles

The system uses a hierarchical template structure based on ZFS snapshots to optimize container creation. Templates are built first, each creating a snapshot that serves as the base for cloning subsequent templates or final application containers.

### Base Layer
*   **`900` (`BaseTemplate`):**
    *   Provides a minimal, generic Ubuntu 24.04 environment.
    *   Serves as the foundation for all other templates.

### Specialized Template Layers
*   **`901` (`BaseTemplateGPU`):** Clones from `900`. Adds NVIDIA GPU drivers/CUDA.
*   **`902` (`BaseTemplateDocker`):** Clones from `900`. Adds Docker Engine and NVIDIA Container Toolkit.
*   **`920` (`BaseTemplateVLLM`):** Clones from `901`. Adds the vLLM serving framework directly (no Docker).

### Final Application Containers
*   **`910` (`Portainer`):** Clones from `902`. A Docker-enabled container running the Portainer Server for managing Docker environments.
*   **`950` (`vllmQwen3Coder`):** Clones from `920`. A GPU+vLLM container configured to serve a specific large language model (Qwen3 Coder 30B) directly (no Docker).

## Application Script Guidelines

When creating an `application_script` for a new container, developers must adhere to the following rules to ensure compatibility with the orchestrator's execution model:

1.  **Execution Context:** Be aware that the script is executed *inside* the container in a temporary directory (`/tmp/phoenix_run`). It is not run on the Proxmox host.
2.  **No Host-Level Commands:** The script **must not** call any Proxmox-specific commands that only exist on the host (e.g., `pct`, `qm`). All operations must be performed using standard Linux commands available within the container's OS.
3.  **Configuration File Access:** If the script needs to read from `phoenix_lxc_configs.json`, it should do so via the helper functions in `common_utils.sh` (e.g., `jq_get_value`). The common utils script will automatically find the configuration file, which the orchestrator copies into the temporary execution directory.
4.  **Idempotency:** Application scripts, like feature scripts, should be idempotent where possible. Rerunning the orchestrator should not break a container that is already correctly configured.

## Container Details

| CTID | Name | Type | Clone Source CTID | Clone Source Snapshot | Key Features | Role/Function |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 900 | `BaseTemplate` | Template | - (Created) | - | Minimal Ubuntu 24.04, 2GB RAM, 2 CPU | Foundational OS template for all other containers. |
| 901 | `BaseTemplateGPU` | Template | 900 | `base-snapshot` | GPU Access (0,1), 2GB RAM, 2 CPU | Template adding NVIDIA drivers/CUDA. |
| 902 | `BaseTemplateDocker` | Template | 900 | `base-snapshot` | Docker-in-LXC (nesting=1), 2GB RAM, 2 CPU | Template adding Docker Engine & NVIDIA Container Toolkit. |
| 920 | `BaseTemplateVLLM` | Template | 901 | `gpu-snapshot` | GPU Access (0,1), vLLM, 4GB RAM, 4 CPU | Template adding the vLLM serving framework directly. |
| 910 | `Portainer` | App | 902 | `docker-snapshot` | Docker-in-LXC, Portainer Server, 32GB RAM, 6 CPU | Runs the Portainer management web UI. |
| 950 | `vllmQwen3Coder` | App | 920 | `vllm-base-snapshot` | GPU Access (0,1), vLLM Qwen3 Model, 40GB RAM, 8 CPU | Serves the Qwen3 Coder 30B LLM via vLLM directly. |

## Notes

*   **Templates:** Containers marked as "Template" are used to create ZFS snapshots (`template_snapshot_name`) after their specific setup script (`phoenix_hypervisor_setup_<CTID>.sh`) finalizes their environment. These snapshots are the basis for cloning.
*   **Application Containers:** Containers marked as "App" are final, functional containers. They are cloned from a template snapshot and configured by their specific setup script for their unique role.
*   **Cloning:** The `clone_from_template_ctid` field in `phoenix_lxc_configs.json` explicitly defines the parent template for each container/template in the hierarchy.
*   **Specific Setup Scripts:** Each container's unique finalization (e.g., starting Portainer, serving a specific model) is handled by its corresponding `phoenix_hypervisor_setup_<CTID>.sh` script.
