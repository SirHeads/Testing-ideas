---
title: 'Feature: Portainer'
summary: The `portainer` feature automates the deployment of Portainer Server or Agent as a Docker container, based on the container's assigned `portainer_role`.
document_type: "Feature Summary"
status: "Approved"
version: "1.0.0"
author: "Phoenix Hypervisor Team"
owner: "Developer"
tags:
  - "Portainer"
  - "Docker"
  - "Container Management"
review_cadence: "Annual"
last_reviewed: "2025-09-30"
---

The `portainer` feature automates the deployment of Portainer within a Docker-enabled LXC container. It provides a centralized web UI for managing Docker environments across the hypervisor.

## Key Actions

The script's behavior is determined by the `portainer_role` defined in the container's configuration (`phoenix_lxc_configs.json`):

1.  **Role-Based Deployment:**
    *   If `portainer_role` is `server`, it deploys the `portainer/portainer-ce:latest` Docker container.
    *   If `portainer_role` is `agent`, it deploys the `portainer/agent` Docker container.
    *   If `portainer_role` is `none` or not specified, the script takes no action.

2.  **Server Configuration:** When deploying the server, the script:
    *   Exposes ports `9443` (for the UI/API) and `9001` (for the agent).
    *   Mounts the host's Docker socket (`/var/run/docker.sock`) to manage the local environment.
    *   Creates a persistent named volume (`portainer_data`) for Portainer's database.
    *   Mounts SSL certificates from a shared volume (`/certs`) for secure access.

3.  **Agent Configuration:** When deploying the agent, the script:
    *   Exposes port `9001`.
    *   Mounts the host's Docker socket and volumes directory.
    *   Configures the agent to connect to the Portainer server using the `AGENT_CLUSTER_ADDR` environment variable.

## Idempotency

The script is idempotent. Before deploying a container, it checks if a container with the target name (`portainer` or `portainer_agent`) is already running. If it is, the deployment is skipped.

## Usage

This feature is applied to containers designated for Docker management. It has a hard dependency on the `docker` feature, which must be installed and running before this script is executed.