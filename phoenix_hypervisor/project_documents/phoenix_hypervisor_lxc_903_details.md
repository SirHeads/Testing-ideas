# LXC Container 903 - `BaseTemplateDockerGPU` - Details

## Overview

This document details the purpose, configuration, and setup process for LXC container `903`, named `BaseTemplateDockerGPU`. This container serves as a combined template level in the Phoenix Hypervisor's snapshot-based hierarchy, integrating both Docker and GPU support. It is created by cloning the `docker-snapshot` from container `902` (`BaseTemplateDocker`) and then configured with the full NVIDIA GPU software stack *inside* the container. It is never intended to be used as a final, running application container. Templates requiring both Docker and GPU support (`920`) and standard application containers needing both will be created by cloning the `docker-gpu-snapshot` taken from this template.

## Purpose

LXC container `903`'s primary purpose is to provide a standardized Ubuntu 24.04 environment with both Docker Engine (inherited from `902`) and the full NVIDIA GPU software stack (drivers, CUDA) pre-installed and configured *inside the container*. This allows containers *running inside this LXC* to leverage Docker and access the host's GPUs, while the LXC itself also has direct GPU access. It serves as the foundational layer for all other templates and containers that require both Docker-in-LXC and direct GPU capabilities. It is exclusively used for cloning; a ZFS snapshot (`docker-gpu-snapshot`) is created after its initial setup for other Docker-and-GPU-dependent containers/templates to clone from.

## Configuration (`phoenix_lxc_configs.json`)

*   **CTID:** `903`
*   **Name:** `BaseTemplateDockerGPU`
*   **Template Source:** Cloned from `902`'s `docker-snapshot` (BaseTemplateDocker)
*   **Resources:**
    *   **CPU Cores:** `2` (Minimal allocation, suitable for base OS, Docker, and GPU setup)
    *   **Memory:** `2048` MB (2 GB RAM, sufficient for base OS and setup tools)
    *   **Storage Pool:** `lxc-disks`
    *   **Storage Size:** `32` GB (Small root filesystem, intended to be expanded by cloning containers as needed)
*   **Network Configuration:**
    *   **Interface:** `eth0`
    *   **Bridge:** `vmbr0`
    *   **IP Address (Placeholder):** `10.0.0.203/24` (This IP is for template consistency and will be changed upon cloning. Using `.203` avoids overlap with common application IPs like `.99` or `.110`)
    *   **Gateway:** `10.0.0.1`
    *   **MAC Address (Placeholder):** `52:54:00:AA:BB:CF` (Will be changed upon cloning)
*   **LXC Features:** `nesting=1` (Essential feature inherited from `902` to enable Docker-in-LXC functionality)
*   **Security & Privileges:**
    *   **Unprivileged:** `false` (Runs in privileged mode, necessary for full GPU access within the container)
*   **GPU Assignment:** `0,1` (Configured to have direct access to both host GPUs, making the template versatile for any Docker/GPU-dependent clone)
*   **Portainer Role:** `none` (Not a Portainer component)
*   **Template Metadata (for Snapshot Hierarchy):**
    *   **`is_template`:** `true` (Identifies this configuration as a template)
    *   **`template_snapshot_name`:** `docker-gpu-snapshot` (Name of the ZFS snapshot this template will produce)
    *   **`clone_from_template_ctid`:** `902` (Indicates this template is created by cloning from container `902`)

## Specific Setup Script (`phoenix_hypervisor/bin/phoenix_hypervisor_lxc_903.sh`) Requirements

The `phoenix_hypervisor/bin/phoenix_hypervisor_lxc_903.sh` script is responsible for the final configuration *verification* of the `BaseTemplateDockerGPU` container *after* it has been cloned from `902`'s `docker-snapshot` and booted. Its core responsibilities are:

*   **Verify Inherited Docker Setup:**
    *   Ensures the container is fully booted.
    *   Confirms that Docker Engine, the NVIDIA Container Toolkit, and the Docker service (inherited from `902`) are correctly configured and running. This might involve checking `systemctl is-active docker` and `docker info`.
*   **Verify In-Container GPU Software Stack:**
    *   This script *verifies* the NVIDIA GPU software stack (drivers, CUDA, `nvidia-smi`, `nvtop`) is correctly installed and configured *inside the container*. The installation of this stack is assumed to have occurred prior to this script's execution (e.g., as part of the `phoenix_hypervisor_lxc_common_nvidia.sh` script or during the setup of the base template 902).
    *   It also verifies that the Docker daemon inside the container is configured to register the NVIDIA runtime, ensuring Docker containers can easily access GPUs.
*   **Verification Steps:**
    *   Runs `nvidia-smi` inside the container and displays the output to confirm direct GPU access.
    *   Runs checks to ensure the Docker environment is correctly set up for GPU use:
        *   `docker info`: Verifies the Docker service is running and the NVIDIA runtime is listed.
        *   `docker pull nvidia/cuda:12.8.0-base-ubuntu24.04`: Pulls the test image.
        *   `docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi`: Runs a simple NVIDIA CUDA container to test end-to-end Docker GPU access.
*   **Finalize and Snapshot Creation:**
    *   Once both the direct GPU environment and the Docker GPU environment are verified, the script's final step is to shut down the container.
    *   It then executes `pct snapshot create 903 docker-gpu-snapshot` to create the ZFS snapshot that forms the basis for the combined Docker/GPU template hierarchy.
    *   Finally, it restarts the container.

## Interaction with Phoenix Hypervisor System

*   **Creation:** `phoenix_establish_hypervisor.sh` will identify `903` as a template (`is_template: true`) and see that `clone_from_template_ctid: "902"`. It will therefore call the cloning process (`phoenix_hypervisor_clone_lxc.sh`) to create `903` by cloning `902`'s `docker-snapshot`.
*   **Setup:** After cloning and initial boot, `phoenix_establish_hypervisor.sh` will execute `phoenix_hypervisor_lxc_903.sh`.
*   **Consumption:** Other templates (e.g., `920` - `BaseTemplateVLLM`) or standard containers needing both Docker and GPU can have `clone_from_template_ctid: "903"` in their configuration. The orchestrator will use this to determine they should be created by cloning `903`'s `docker-gpu-snapshot`.
*   **Idempotency:** The setup script (`phoenix_hypervisor_lxc_903.sh`) must be idempotent. If `docker-gpu-snapshot` already exists, it should skip the setup steps and potentially just log that the template is already prepared.

## Requirements

*   Proxmox host environment with `pct` command available.
*   Container 903 must be created/cloned and accessible.
*   `jq` (for parsing JSON configuration files).
*   `phoenix_hypervisor_lxc_common_nvidia.sh` and `phoenix_hypervisor_lxc_common_docker.sh` must have been executed successfully on parent templates or during this container's setup.

## Exit Codes

*   `0`: Success (Setup completed, snapshot created or already existed).
*   `1`: General error.
*   `2`: Invalid input arguments.
*   `3`: Container 903 does not exist or is not accessible.
*   `4`: Docker/NVIDIA verification failed.
*   `5`: Snapshot creation failed.
*   `6`: Container shutdown/start failed.

## Key Characteristics Summary

*   **Docker & GPU Base:** Provides the core OS plus Docker Engine, NVIDIA Container Toolkit, and the full NVIDIA GPU software stack (drivers, CUDA) inside the container.
*   **Privileged Mode:** Runs privileged (`unprivileged: false`) to ensure full GPU access.
*   **Generic Network:** Uses placeholder IP/MAC (`.203`) which are changed on clone to avoid conflicts.
*   **Dual GPU Access:** Configured for direct access to GPUs 0 and 1.
*   **Template Only:** Never used as a final application container.
*   **Snapshot Source:** The origin of the `docker-gpu-snapshot` ZFS snapshot for containers requiring both Docker-in-LXC and GPU access.