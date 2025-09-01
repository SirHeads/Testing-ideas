# Feature: NVIDIA

## Summary

The `nvidia` feature automates the entire process of enabling NVIDIA GPU access for an LXC container. It handles both the host-side configuration for device passthrough and the installation of the necessary drivers and toolkits inside the container.

### RAG Keywords
NVIDIA, GPU, CUDA, driver installation, passthrough, LXC, AI, machine learning

## Key Actions

1.  **Host GPU Passthrough:**
    *   Reads the `gpu_assignment` property from the container's configuration.
    *   Modifies the container's `.conf` file on the Proxmox host to bind-mount the specified GPU devices (e.g., `/dev/nvidia0`) and standard NVIDIA devices (`/dev/nvidiactl`, etc.).
    *   Adds the necessary `cgroup2` device permissions to allow the container access to the GPU hardware.
2.  **Driver & CUDA Installation:**
    *   Installs the NVIDIA driver within the container using the `.run` file specified in the main configuration.
    *   Installs the CUDA toolkit (`cuda-toolkit-12-8`) from the official NVIDIA repository.
3.  **Verification:** Runs `nvidia-smi` inside the container to verify that the GPU is successfully recognized and the drivers are functioning correctly.
4.  **Idempotency:** The script checks if `nvidia-smi` is already functional within the container before attempting installation, preventing redundant operations.

## Usage

This feature is applied to any container that requires direct access to the host's NVIDIA GPUs for accelerated computing tasks. It is a prerequisite for GPU-accelerated Docker containers and applications like vLLM.