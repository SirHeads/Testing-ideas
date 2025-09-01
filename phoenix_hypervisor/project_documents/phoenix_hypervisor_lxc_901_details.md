# LXC Container 901 - `BaseTemplateGPU` - Details

## Overview

This document details the purpose, configuration, and setup process for LXC container `901`, named `BaseTemplateGPU`. This container serves as the first level in the Phoenix Hypervisor's snapshot-based GPU template hierarchy. It is created by cloning the `base-snapshot` from container `900` (`BaseTemplate`) and is specifically configured with the necessary NVIDIA drivers and CUDA toolkit. It is never intended to be used as a final, running application container. Templates requiring GPU support (`920`) and standard GPU-enabled application containers will be created by cloning the `gpu-snapshot` taken from this template.

## Purpose

LXC container `901`'s primary purpose is to provide a standardized Ubuntu 24.04 environment with the full NVIDIA GPU software stack (drivers, CUDA) pre-installed and configured. This serves as the foundational layer for all other templates and containers that require GPU access. It is exclusively used for cloning; a ZFS snapshot (`gpu-snapshot`) is created after its initial setup for other GPU-dependent containers/templates to clone from.

## Configuration (`phoenix_lxc_configs.json`)

*   **CTID:** `901`
*   **Name:** `BaseTemplateGPU`
*   **Template Source:** `/fastData/shared-iso/template/cache/ubuntu-24.04-standard_24.04-2_amd64.tar.zst`
*   **Resources:**
    *   **CPU Cores:** `2` (Minimal allocation, suitable for base OS and driver setup)
    *   **Memory:** `2048` MB (2 GB RAM, sufficient for base OS and GPU setup tools)
    *   **Storage Pool:** `lxc-disks`
    *   **Storage Size:** `32` GB (Small root filesystem, intended to be expanded by cloning containers as needed)
*   **Network Configuration:**
    *   **Interface:** `eth0`
    *   **Bridge:** `vmbr0`
    *   **IP Address (Placeholder):** `10.0.0.201/24` (This IP is for template consistency and will be changed upon cloning. Using `.201` avoids overlap with common application IPs like `.99` or `.110`)
    *   **Gateway:** `10.0.0.1`
    *   **MAC Address (Placeholder):** `52:54:00:AA:BB:CD` (Will be changed upon cloning)
*   **LXC Features:** `` (Empty string, no special features enabled at this base level. LXC configuration for GPU access is handled by the setup script modifying the container config file).
*   **Security & Privileges:**
    *   **Unprivileged:** `true` (Runs in unprivileged mode, which is more secure)
*   **GPU Assignment:** `0,1` (Configured to have access to both host GPUs, making the template versatile for any GPU-dependent clone)
*   **Portainer Role:** `none` (Not a Portainer component)
*   **Template Metadata (for Snapshot Hierarchy):**
    *   **`is_template`:** `true` (Identifies this configuration as a template)
    *   **`template_snapshot_name`:** `gpu-snapshot` (Name of the ZFS snapshot this template will produce)
    *   **`clone_from_template_ctid`:** `900` (Indicates this template is created by cloning from container `900`)

## Specific Setup Script (`phoenix_hypervisor/bin/phoenix_hypervisor_lxc_901.sh`) Requirements

The `phoenix_hypervisor/bin/phoenix_hypervisor_lxc_901.sh` script is responsible for the final configuration of the `BaseTemplateGPU` container *after* it has been cloned from `900`'s `base-snapshot` and booted. Its core responsibilities are:

*   **GPU Software Stack Installation:**
    *   Ensures the container is fully booted and ready for setup.
    *   Executes the common NVIDIA setup process. This will likely involve calling or replicating the logic from `phoenix_hypervisor_lxc_common_nvidia.sh`.
    *   This process will install the NVIDIA driver, CUDA toolkit, and utilities (`nvidia-smi`, `nvtop`) inside the container. The specific versions are sourced dynamically from `phoenix_lxc_configs.json`.
    *   It will configure the container's LXC config (on the host) to correctly pass through GPU devices (`/dev/nvidia*`, `/dev/nvidia-caps/*`) based on the `gpu_assignment: "0,1"`.
*   **Verification:**
    *   After installation, runs `nvidia-smi` inside the container and displays the output to the terminal/log to confirm the drivers are correctly installed and can see the assigned GPUs.
*   **Finalize and Snapshot Creation:**
    *   Once the GPU environment is verified, the script's final step is to shut down the container.
    *   It then executes `pct snapshot create 901 gpu-snapshot` to create the ZFS snapshot that forms the basis for the GPU template hierarchy.
    *   Finally, it restarts the container.

## Interaction with Phoenix Hypervisor System

*   **Creation:** `phoenix_establish_hypervisor.sh` will identify `901` as a template (`is_template: true`) and see that `clone_from_template_ctid: "900"`. It will therefore call the cloning process (`phoenix_hypervisor_clone_lxc.sh`) to create `901` by cloning `900`'s `base-snapshot`.
*   **Setup:** After cloning and initial boot, `phoenix_establish_hypervisor.sh` will execute `phoenix_hypervisor_lxc_901.sh`.
*   **Consumption:** Other templates (e.g., `920` - `BaseTemplateVLLM`) or standard containers needing GPUs can have `clone_from_template_ctid: "901"` in their configuration. The orchestrator will use this to determine they should be created by cloning `901`'s `gpu-snapshot`.
*   **Idempotency:** The setup script (`phoenix_hypervisor_lxc_901.sh`) must be idempotent. If `gpu-snapshot` already exists, it should skip the GPU setup steps and potentially just log that the template is already prepared.

## Requirements

*   Proxmox host environment with `pct` command available.
*   Container 901 must be created/cloned and accessible.
*   `jq` (for parsing JSON configuration files).
*   `phoenix_hypervisor_lxc_common_nvidia.sh` must be available and functional.
*   Global NVIDIA settings (driver version, repository URL, runfile URL) must be defined in `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`.

## Exit Codes

*   `0`: Success (Setup completed, snapshot created or already existed).
*   `1`: General error.
*   `2`: Invalid input arguments.
*   `3`: Container 901 does not exist or is not accessible.
*   `4`: NVIDIA driver/CUDA installation/configuration failed.
*   `5`: Snapshot creation failed.
*   `6`: Container shutdown/start failed.

## Key Characteristics Summary

*   **GPU Base:** Provides the core OS plus the full NVIDIA GPU software stack.
*   **Unprivileged Mode:** Runs unprivileged (`unprivileged: true`) for enhanced security.
*   **Generic Network:** Uses placeholder IP/MAC (`.201`) which are changed on clone to avoid conflicts.
*   **Dual GPU Access:** Configured for GPUs 0 and 1 by default.
*   **Template Only:** Never used as a final application container.
*   **Snapshot Source:** The origin of the `gpu-snapshot` ZFS snapshot for GPU-dependent containers.