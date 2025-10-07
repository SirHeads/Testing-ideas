---
title: 'Feature: Docker'
summary: The `docker` feature is a foundational component of the infrastructure layer. It automates the installation and configuration of the Docker engine within a VM, preparing it to host Docker workloads. Portainer integration and stack deployment are handled by the `portainer-manager.sh`.
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
The `docker` feature is a prerequisite for any VM that will be used to run Docker workloads. It installs the Docker engine and prepares the VM as a Docker host. Management of Docker environments and deployment of stacks are handled by the `portainer-manager.sh`.

## Key Actions

1.  **Docker Engine Installation:** Adds the official Docker repository and installs the latest versions of `docker-ce`, `docker-ce-cli`, and `containerd.io`.
2.  **Secure Storage Driver (LXC only):** When used in an LXC container, it installs `fuse-overlayfs` and configures Docker's `daemon.json` to use it as the storage driver. This is a critical security measure for running Docker inside unprivileged LXC containers.
3.  **Conditional NVIDIA Container Toolkit:** If the `nvidia` feature is present on the container, it installs the `nvidia-container-toolkit` and merges the necessary configuration into `daemon.json` to set `nvidia` as the default runtime, enabling GPU access for Docker containers.
4.  **Idempotency:** The script checks if the `docker` command is already available in the container. If it is, the installation process is skipped, ensuring the script can be re-run safely.

## Usage

This feature is applied to any VM that is intended to run Docker workloads. It is a prerequisite for any Docker-based environment and is typically listed in the `features` array in `phoenix_vm_configs.json`. The deployment and management of Portainer and Docker stacks on top of this Docker engine are handled by the `portainer-manager.sh`.
