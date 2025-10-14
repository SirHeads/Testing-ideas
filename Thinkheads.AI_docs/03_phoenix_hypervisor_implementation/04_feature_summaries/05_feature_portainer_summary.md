---
title: 'Feature: Portainer'
summary: The Portainer integration is now managed by the dedicated `portainer-manager.sh` script, which orchestrates the deployment of the Portainer server and agents, and drives the declarative stack management system via the Portainer API.
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

The Portainer integration is now a core component of the declarative environment management layer, orchestrated by `portainer-manager.sh`. It is no longer just a management UI, but the engine that drives the entire stack deployment workflow.

## Key Actions

1.  **Portainer Instance Deployment**: The `portainer-manager.sh` deploys the `portainer/portainer-ce:latest` Docker container as the server in a dedicated VM (typically VM 1001) and `portainer/agent:latest` containers as agents on other Docker-enabled VMs.
2.  **API-Driven Environment Management**: The `portainer-manager.sh` authenticates with the Portainer API to create and manage environments (endpoints) for each agent-enabled VM.
3.  **Declarative Stack Orchestration**: The `portainer-manager.sh` reads the desired state of Docker stacks from configuration files and uses the Portainer API to deploy, update, or remove stacks on the configured environments.

## Architectural Shift: VM-Based Deployment

Originally, Portainer was deployed inside an LXC container. Due to stability and security concerns related to running Docker in a nested, unprivileged container, the architecture has been updated. The standard practice is now to deploy all Docker-dependent services, including Portainer, into a dedicated VM.

This architectural shift is critical for system stability and is documented in the **[Docker-in-LXC Deprecation Plan](../00_guides/12_docker_lxc_issue_mitigation_plan.md)**, which outlines the formal deprecation of running Docker inside LXC containers.

## Idempotency

The script is idempotent. Before deploying a container, it checks if a container with the target name (`portainer` or `portainer_agent`) is already running. If it is, the deployment is skipped.

## Usage

The Portainer environment is a foundational component of the declarative environment management layer. It is deployed and managed by the `portainer-manager.sh` script, which is invoked by the `phoenix-cli sync portainer` command or automatically as part of the `phoenix-cli LetsGo` workflow. The `docker` feature is a prerequisite for any VM hosting Portainer instances.