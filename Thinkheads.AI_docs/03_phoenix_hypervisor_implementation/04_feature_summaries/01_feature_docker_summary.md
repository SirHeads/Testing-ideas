---
title: 'Feature: Docker'
summary: The `docker` feature automates the complete installation and configuration of a containerization environment within an LXC container, including Docker Engine, the secure `fuse-overlayfs` storage driver, and the NVIDIA Container Toolkit for GPU-enabled workloads.
document_type: "Feature Summary"
status: "Approved"
version: "1.0.0"
author: "Phoenix Hypervisor Team"
owner: "Developer"
tags:
  - "Docker"
  - "Containerization"
  - "NVIDIA Container Toolkit"
  - "fuse-overlayfs"
  - "GPU"
  - "Container Runtime"
review_cadence: "Annual"
last_reviewed: "2025-09-23"
---
The `docker` feature automates the complete installation and configuration of a containerization environment within an LXC container. It installs Docker Engine, configures the `fuse-overlayfs` storage driver for security in unprivileged containers, and, if the `nvidia` feature is also present, installs the NVIDIA Container Toolkit.

## Key Actions

1.  **Docker Engine Installation:** Adds the official Docker repository and installs the latest versions of `docker-ce`, `docker-ce-cli`, `containerd.io`, and the `docker-compose-plugin`.
2.  **Secure Storage Driver:** Installs `fuse-overlayfs` and configures Docker's `daemon.json` to use it as the storage driver. This is a critical security measure for running Docker inside unprivileged LXC containers.
3.  **Conditional NVIDIA Container Toolkit:** If the `nvidia` feature is present on the container, it installs the `nvidia-container-toolkit` and merges the necessary configuration into `daemon.json` to set `nvidia` as the default runtime, enabling GPU access for Docker containers.
4.  **Idempotency:** The script checks if the `docker` command is already available in the container. If it is, the installation process is skipped, ensuring the script can be re-run safely.

## Usage

This feature is applied to any container that needs to run Docker workloads. It is a prerequisite for features that rely on containerization, such as the `portainer` and `vllm` features. If GPU support is required, the `nvidia` feature must be listed before `docker` in the `features` array.
