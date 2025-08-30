# `phoenix_hypervisor_lxc_common_nvidia.sh` - Summary

## Overview

This document summarizes the purpose, responsibilities, and key interactions of the `phoenix_hypervisor_lxc_common_nvidia.sh` script within the Phoenix Hypervisor system.

## Purpose

The `phoenix_hypervisor_lxc_common_nvidia.sh` script is responsible for configuring NVIDIA GPU support *inside* a specific LXC container. This involves passing through the required host GPU devices and installing/configuring the NVIDIA driver, CUDA toolkit, and related utilities within the container's filesystem to enable GPU-accelerated applications.

## Key Responsibilities

*   **Conditional Execution:**
    *   Designed to be called by `phoenix_establish_hypervisor.sh` only for containers where `config_block.gpu_assignment` is not `"none"`.
*   **GPU Passthrough Configuration (Host):**
    *   Receives the `CTID` and `gpu_assignment` string (e.g., "0", "1", "0,1") from the orchestrator.
    *   Maps GPU indices from `gpu_assignment` to host device files (e.g., "0" -> `/dev/nvidia0`).
    *   Verifies the existence of the corresponding host GPU device files.
    *   Modifies the LXC container's configuration file on the Proxmox host (e.g., `/etc/pve/lxc/<CTID>.conf`).
    *   Adds `lxc.mount.entry` lines to bind-mount the necessary NVIDIA device files (`/dev/nvidia*`) and the `/dev/nvidia-caps` directory from the host into the container's filesystem.
*   **NVIDIA Software Installation (Container):**
    *   Receives the `nvidia_driver_version` (e.g., "580.76.05") and `nvidia_repo_url` from the orchestrator.
    *   Uses `pct exec` (or similar) to run commands inside the specified LXC container.
    *   Adds the NVIDIA CUDA repository (`nvidia_repo_url`) inside the container.
    *   Downloads and executes the official NVIDIA Driver `.run` installer (matching `nvidia_driver_version`) inside the container, using flags like `--no-kernel-module` (as the kernel module runs on the host).
    *   Installs the CUDA toolkit and runtime libraries (matching the driver version, likely CUDA 12.8) inside the container using `apt` from the added repository.
    *   Installs diagnostic/utilities like `nvtop` inside the container using `apt`.
*   **Verification (Container):**
    *   Runs `nvidia-smi` inside the container to verify the driver installation and display GPU status.
    *   Uses `nvidia-smi --version` (or similar checks) for idempotency to determine if setup has already been successfully completed within the container.
*   **Container Restart (Host/Container):**
    *   Restarts the LXC container using `pct` commands to ensure the new device mounts and configurations are applied.
*   **Execution Context:**
    *   Runs non-interactively on the Proxmox host.
    *   Uses `pct exec` (or potentially SSH) to execute commands inside the target LXC container.
    *   Modifies LXC configuration files on the Proxmox host filesystem.
*   **Idempotency:**
    *   Designed to be safe to run multiple times. Checks for the existence of the driver/software inside the container before attempting installation/configuration.
*   **Logging & Error Handling:**
    *   Provides detailed logs of the process, including host configuration changes, commands run inside the container, and verification outputs.
    *   Reports success or failure back to the calling orchestrator (`phoenix_establish_hypervisor.sh`) via a standard exit code (0 for success, non-zero for failure).

## Interaction with Other Components

*   **Called By:** `phoenix_establish_hypervisor.sh` for containers requiring GPU support.
*   **Input:** `CTID`, `gpu_assignment` string, `nvidia_driver_version`, `nvidia_repo_url`.
*   **Configuration Source:** Relies on information passed from the orchestrator, which originates from `phoenix_lxc_configs.json` and `phoenix_hypervisor_config.json`.
*   **Reports To:** `phoenix_establish_hypervisor.sh` via exit code and logs.
*   **Precedes:** Potentially `phoenix_hypervisor_lxc_docker.sh` (if Docker is also configured in the container) and `phoenix_hypervisor_setup_<CTID>.sh`, which are called by the orchestrator after this script completes successfully.

## Output & Error Handling

*   **Output:** Detailed logs indicating the steps taken on the host (config modification) and inside the container (software installation, verification), including the output of `nvidia-smi`.
*   **Error Handling:** Specific exit codes (0 for success, 2 for invalid input, 3 for container not found, 4 for host configuration error, 5 for software installation error, 6 for container restart error) to communicate status to the orchestrator. Detailed logging provides context for any failures, such as missing host devices, `pct exec` failures, or package installation errors.