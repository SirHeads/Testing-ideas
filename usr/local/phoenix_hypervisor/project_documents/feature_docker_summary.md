---
title: 'Feature: Docker'
summary: The `docker` feature automates the complete installation and configuration of a containerization environment within an LXC container.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Docker
- Containerization
- NVIDIA Container Toolkit
- Portainer
- GPU
- Container Runtime
review_cadence: Annual
last_reviewed: 2025-09-23
---
The `docker` feature automates the complete installation and configuration of a containerization environment within an LXC container. It installs Docker Engine, the NVIDIA Container Toolkit, and can deploy Portainer for management.

## Key Actions

1.  **Docker Engine Installation:** Adds the official Docker repository and installs the latest versions of `docker-ce`, `docker-ce-cli`, `containerd.io`, and the `docker-compose-plugin`.
2.  **NVIDIA Container Toolkit:** Installs the `nvidia-container-toolkit` and configures Docker's `daemon.json` to use `nvidia` as the default runtime, enabling GPU access for Docker containers.
3.  **Portainer Deployment:** Reads the `portainer_role` from the container's configuration and will:
    *   Deploy the Portainer Server container if the role is `server`.
    *   Deploy the Portainer Agent container if the role is `agent`.
    *   Do nothing if the role is `none`.
4.  **Idempotency:** The script includes checks to see if Docker is already installed and running, and if the specified Portainer container already exists, preventing redundant operations.

## Usage

This feature is applied to any container that needs to run Docker workloads. It is a prerequisite for features that rely on containerization, such as the `vllm` feature.
