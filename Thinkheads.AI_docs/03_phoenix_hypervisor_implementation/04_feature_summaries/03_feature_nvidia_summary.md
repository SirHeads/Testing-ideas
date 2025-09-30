---
title: 'Feature: NVIDIA GPU Driver'
summary: The `nvidia` feature enables GPU acceleration within an LXC container by performing a two-phase installation of the user-space driver and CUDA toolkit, ensuring alignment with the host kernel driver.
document_type: "Feature Summary"
status: "Approved"
version: "1.0.0"
author: "Phoenix Hypervisor Team"
owner: "Developer"
tags:
  - "NVIDIA"
  - "GPU"
  - "CUDA"
  - "Driver Installation"
  - "Hardware Passthrough"
review_cadence: "Annual"
last_reviewed: "2025-09-30"
---

The `nvidia` feature is a critical component for enabling high-performance GPU workloads within an LXC container. It follows a "Host-Kernel, Container-Userspace" architecture to safely and efficiently pass through NVIDIA GPU devices from the Proxmox host to the container.

## Key Actions

The script operates in two distinct phases:

1.  **Host-Side Configuration:**
    *   **GPU Passthrough:** Modifies the container's configuration file (`/etc/pve/lxc/<CTID>.conf`) on the Proxmox host to grant the container access to the assigned GPU device nodes.
    *   **Device Mapping:** Adds `lxc.cgroup2.devices.allow` and `lxc.mount.entry` lines to bind-mount the necessary `/dev/nvidia*` devices into the container.
    *   **Container Restart:** Restarts the container to apply the new hardware configuration.

2.  **Container-Side Installation:**
    *   **User-Space Driver Installation:** Downloads and executes the official NVIDIA driver `.run` file inside the container with the `--no-kernel-module` flag. This is a critical step that installs only the user-space libraries (like `nvidia-smi`) and ensures they match the version of the kernel driver running on the host.
    *   **CUDA Toolkit Installation:** Installs the appropriate CUDA Toolkit from the official NVIDIA repository, providing the necessary compilers (`nvcc`) and libraries for GPU-accelerated applications.
    *   **Verification:** Confirms that `nvidia-smi` and `nvcc` are executable and functional inside the container.

## Idempotency

The script is idempotent. It checks for the existence of `nvidia-smi` inside the container and will skip the container-side installation if it is already present. On the host, it checks if the passthrough configuration lines already exist in the container's `.conf` file before adding them.

## Usage

This feature is applied to any container that requires GPU acceleration. It is a foundational feature and a prerequisite for other features like `docker` (when GPU support is needed), `ollama`, and `vllm`.