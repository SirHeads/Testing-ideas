# LXC Container 902 - BaseTemplateDocker - Requirements & Details

## Overview

This document details the purpose, configuration, and setup process for LXC container `902`, named `BaseTemplateDocker`. This container serves as the first level in the Phoenix Hypervisor's snapshot-based Docker template hierarchy. It is created by cloning the `base-snapshot` from container `900` (`BaseTemplate`) and is specifically configured with Docker Engine and the NVIDIA Container Toolkit. It is never intended to be used as a final, running application container. Templates requiring Docker support (`903`) and standard Docker-enabled application containers will be created by cloning the `docker-snapshot` taken from this template.

## Core Purpose & Function

*   **Role:** Docker-Enabled Base Template.
*   **Primary Function:** Provide a standardized Ubuntu 24.04 environment with Docker Engine and the NVIDIA Container Toolkit pre-installed and configured. This allows containers *running inside this LXC* to leverage Docker and potentially access the host's GPUs. It serves as the foundational layer for all other templates and containers that require Docker-in-LXC.
*   **Usage:** Exclusively used for cloning. A ZFS snapshot (`docker-snapshot`) is created after its initial setup for other Docker-dependent containers/templates to clone from.

## Configuration (`phoenix_lxc_configs.json`)

*   **CTID:** `902`
*   **Name:** `BaseTemplateDocker`
*   **Template Source:** `/fastData/shared-iso/template/cache/ubuntu-24.04-standard_24.04-2_amd64.tar.zst`
*   **Resources:**
    *   **CPU Cores:** `2` (Minimal allocation, suitable for base OS and Docker setup)
    *   **Memory:** `2048` MB (2 GB RAM, sufficient for base OS and Docker setup tools)
    *   **Storage Pool:** `lxc-disks`
    *   **Storage Size:** `32` GB (Small root filesystem, intended to be expanded by cloning containers as needed)
*   **Network Configuration:**
    *   **Interface:** `eth0`
    *   **Bridge:** `vmbr0`
    *   **IP Address (Placeholder):** `10.0.0.202/24` (This IP is for template consistency and will be changed upon cloning. Using `.202` avoids overlap with common application IPs like `.99` or `.110`)
    *   **Gateway:** `10.0.0.1`
    *   **MAC Address (Placeholder):** `52:54:00:AA:BB:CE` (Will be changed upon cloning)
*   **LXC Features:** `nesting=1` (Essential feature to enable Docker-in-LXC functionality)
*   **Security & Privileges:**
    *   **Unprivileged:** `true` (Runs in unprivileged mode, which is standard and functional for Docker-in-LXC)
*   **GPU Assignment:** `none` (This base Docker template does not itself have GPU access configured; the NVIDIA Container Toolkit allows *Docker containers inside* to access GPUs if the LXC is later configured for it or cloned from a GPU template).
*   **Portainer Role:** `none` (Not a Portainer component)
*   **Template Metadata (for Snapshot Hierarchy):**
    *   **`is_template`:** `true` (Identifies this configuration as a template)
    *   **`template_snapshot_name`:** `docker-snapshot` (Name of the ZFS snapshot this template will produce)
    *   **`clone_from_template_ctid`:** `900` (Indicates this template is created by cloning from container `900`)

## Specific Setup Script (`phoenix_hypervisor_setup_902.sh`) Requirements

The `phoenix_hypervisor_setup_902.sh` script is responsible for the final configuration of the `BaseTemplateDocker` container *after* it has been cloned from `900`'s `base-snapshot` and booted. Its core responsibilities are:

1.  **Docker Software Stack Installation:**
    *   Ensure the container is fully booted and ready for setup.
    *   Execute the common Docker setup process. This will likely involve calling or replicating the logic from `phoenix_hypervisor_lxc_docker.sh`.
    *   This process will install Docker Engine, the NVIDIA Container Toolkit, and `docker-compose-plugin` inside the container.
    *   It will add the default user (e.g., `ubuntu`) to the `docker` group.
    *   It will enable and start the Docker service (`systemctl enable docker --now`).

2.  **Verification:**
    *   After installation and service start, run checks to ensure Docker is functional.
    *   Example checks: `docker info` (to verify service is running and NVIDIA runtime is registered), `docker run hello-world` (to test basic container execution).

3.  **Finalize and Snapshot Creation:**
    *   Once the Docker environment is verified, the script's final step is to shut down the container.
    *   It then executes `pct snapshot create 902 docker-snapshot` to create the ZFS snapshot that forms the basis for the Docker template hierarchy.
    *   Finally, it restarts the container.

## Interaction with Phoenix Hypervisor System

*   **Creation:** `phoenix_establish_hypervisor.sh` will identify `902` as a template (`is_template: true`) and see that `clone_from_template_ctid: "900"`. It will therefore call the cloning process (`phoenix_hypervisor_clone_lxc.sh`) to create `902` by cloning `900`'s `base-snapshot`.
*   **Setup:** After cloning and initial boot, `phoenix_establish_hypervisor.sh` will execute `phoenix_hypervisor_setup_902.sh`.
*   **Consumption:** Other templates (e.g., `903` - `BaseTemplateDockerGPU`) or standard containers needing Docker can have `clone_from_template_ctid: "902"` in their configuration. The orchestrator will use this to determine they should be created by cloning `902`'s `docker-snapshot`.
*   **Idempotency:** The setup script (`phoenix_hypervisor_setup_902.sh`) must be idempotent. If `docker-snapshot` already exists, it should skip the Docker setup steps and potentially just log that the template is already prepared.

## Key Characteristics Summary

*   **Docker Base:** Provides the core OS plus Docker Engine and NVIDIA Container Toolkit.
*   **Unprivileged Mode:** Runs unprivileged (`unprivileged: true`) for standard Docker-in-LXC security.
*   **Generic Network:** Uses placeholder IP/MAC (`.202`) which are changed on clone to avoid conflicts.
*   **No Direct GPU Access:** The template itself has `gpu_assignment: "none"`, but the toolkit enables GPU access for *containers running inside it* if GPU passthrough is configured for the LXC.
*   **Template Only:** Never used as a final application container.
*   **Snapshot Source:** The origin of the `docker-snapshot` ZFS snapshot for Docker-dependent containers.