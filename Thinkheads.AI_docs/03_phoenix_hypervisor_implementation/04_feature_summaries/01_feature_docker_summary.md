---
title: 'Feature: Docker'
summary: The `docker` feature automates the complete installation and configuration of a containerization environment within a VM or LXC container, including Docker Engine, and the NVIDIA Container Toolkit for GPU-enabled workloads.
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
The `docker` feature automates the complete installation and configuration of a containerization environment. While it can be used in LXC containers, the recommended approach is to use a dedicated VM for Docker workloads. It installs Docker Engine and, if the `nvidia` feature is also present, installs the NVIDIA Container Toolkit.

## Key Actions

1.  **Docker Engine Installation:** Adds the official Docker repository and installs the latest versions of `docker-ce`, `docker-ce-cli`, `containerd.io`, and the `docker-compose-plugin`.
2.  **Secure Storage Driver:** When used in an LXC container, it installs `fuse-overlayfs` and configures Docker's `daemon.json` to use it as the storage driver. This is a critical security measure for running Docker inside unprivileged LXC containers.
3.  **Conditional NVIDIA Container Toolkit:** If the `nvidia` feature is present on the container, it installs the `nvidia-container-toolkit` and merges the necessary configuration into `daemon.json` to set `nvidia` as the default runtime, enabling GPU access for Docker containers.
4.  **Idempotency:** The script checks if the `docker` command is already available in the container. If it is, the installation process is skipped, ensuring the script can be re-run safely.

## Usage

This feature is applied to any VM or container that needs to run Docker workloads. For most use cases, it is recommended to use a dedicated VM (e.g., VM 8001) for Docker services. If GPU support is required, the `nvidia` feature must be listed before `docker` in the `features` array.
