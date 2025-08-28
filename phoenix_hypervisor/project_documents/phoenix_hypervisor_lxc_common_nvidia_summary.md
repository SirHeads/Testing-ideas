# `phoenix_hypervisor_lxc_nvidia.sh` - Summary

## Overview

This document summarizes the purpose, responsibilities, and key interactions of the `phoenix_hypervisor_lxc_nvidia.sh` script within the Phoenix Hypervisor system.

## Purpose

The `phoenix_hypervisor_lxc_nvidia.sh` script is responsible for configuring NVIDIA GPU support *inside* a specific LXC container. This involves passing through the required host GPU devices and installing/configuring the NVIDIA driver, CUDA toolkit, and related utilities within the container's filesystem to enable GPU-accelerated applications.

## Key Responsibilities

1.  **Conditional Execution:**
    *   Designed to be called by `phoenix_establish_hypervisor.sh` only for containers where `config_block.gpu_assignment` is not `"none"`.

2.  **GPU Passthrough Configuration (Host):**
    *   Receive the `CTID` and `gpu_assignment` string (e.g., "0", "1", "0,1") from the orchestrator.
    *   Map GPU indices from `gpu_assignment` to host device files (e.g., "0" -> `/dev/nvidia0`).
    *   Verify the existence of the corresponding host GPU device files.
    *   Modify the LXC container's configuration file on the Proxmox host (e.g., `/etc/pve/lxc/<CTID>.conf`).
    *   Add `lxc.mount.entry` lines to bind-mount the necessary NVIDIA device files (`/dev/nvidia*`, `/dev/nvidia-caps/*`) and driver libraries from the host into the container's filesystem.

3.  **NVIDIA Software Installation (Container):**
    *   Receive the `nvidia_driver_version` (e.g., "580.76.05") and `nvidia_repo_url` from the orchestrator.
    *   Use `pct exec` (or similar) to run commands inside the specified LXC container.
    *   Add the NVIDIA CUDA repository (`nvidia_repo_url`) inside the container.
    *   Download and execute the official NVIDIA Driver `.run` installer (matching `nvidia_driver_version`) inside the container, using flags like `--no-kernel-module` (as the kernel module runs on the host).
    *   Install the CUDA toolkit and runtime libraries (matching the driver version, likely CUDA 12.8) inside the container using `apt` from the added repository.
    *   Install diagnostic/utilities like `nvtop` inside the container using `apt`.

4.  **Verification (Container):**
    *   Run `nvidia-smi` inside the container to verify the driver installation and display GPU status.
    *   Use `nvidia-smi --version` (or similar checks) for idempotency to determine if setup has already been successfully completed within the container.

5.  **Container Restart (Host/Container):**
    *   Restart the LXC container using `pct` commands to ensure the new device mounts and configurations are applied.

6.  **Execution Context:**
    *   Runs non-interactively on the Proxmox host.
    *   Uses `pct exec` (or potentially SSH) to execute commands inside the target LXC container.
    *   Modifies LXC configuration files on the Proxmox host filesystem.

7.  **Idempotency:**
    *   Designed to be safe to run multiple times. Checks for the existence of the driver/software inside the container before attempting installation/configuration.

8.  **Logging & Error Handling:**
    *   Provide detailed logs of the process, including host configuration changes, commands run inside the container, and verification outputs.
    *   Report success or failure back to the calling orchestrator (`phoenix_establish_hypervisor.sh`) via a standard exit code (0 for success, non-zero for failure).

## Interaction with Other Components

*   **Called By:** `phoenix_establish_hypervisor.sh` for containers requiring GPU support.
*   **Input:** `CTID`, `gpu_assignment` string, `nvidia_driver_version`, `nvidia_repo_url`.
*   **Configuration Source:** Relies on information passed from the orchestrator, which originates from `phoenix_lxc_configs.json` and `phoenix_hypervisor_config.json`.
*   **Reports To:** `phoenix_establish_hypervisor.sh` via exit code and logs.
*   **Precedes:** Potentially `phoenix_hypervisor_lxc_docker.sh` (if Docker is also configured in the container) and `phoenix_hypervisor_setup_<CTID>.sh`, which are called by the orchestrator after this script completes successfully.

## Output & Error Handling

*   **Output:** Detailed logs indicating the steps taken on the host (config modification) and inside the container (software installation, verification), including the output of `nvidia-smi`.
*   **Error Handling:** Standard exit codes (0 for success, non-zero for failure) to communicate status to the orchestrator. Detailed logging provides context for any failures, such as missing host devices, `pct exec` failures, or package installation errors.