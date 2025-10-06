---
title: 'Feature: Portainer'
summary: The `portainer` feature is a critical component of the declarative stack management system. It automates the deployment of the Portainer server and provides the API that drives the entire stack orchestration workflow.
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

The `portainer` feature is now a core component of the declarative stack management system. It is no longer just a management UI, but the engine that drives the entire stack deployment workflow.

## Key Actions

1.  **Portainer Server Deployment**: The feature deploys the `portainer/portainer-ce:latest` Docker container in a dedicated VM (typically VM 1001).
2.  **API Integration**: The `vm-manager.sh` script uses the `portainer_api_setup.sh` utility to interact with the Portainer API. This allows for the programmatic creation of endpoints and the deployment of stacks.
3.  **Declarative Stack Orchestration**: The entire stack deployment process is now declarative. The `phoenix-cli` CLI reads the desired state from the configuration files and uses the Portainer API to make the live system match that state.

## Architectural Shift: VM-Based Deployment

Originally, Portainer was deployed inside an LXC container. Due to stability and security concerns related to running Docker in a nested, unprivileged container, the architecture has been updated. The standard practice is now to deploy all Docker-dependent services, including Portainer, into a dedicated VM.

This architectural shift is critical for system stability and is documented in the **[Docker-in-LXC Deprecation Plan](../00_guides/12_docker_lxc_issue_mitigation_plan.md)**, which outlines the formal deprecation of running Docker inside LXC containers.

## Idempotency

The script is idempotent. Before deploying a container, it checks if a container with the target name (`portainer` or `portainer_agent`) is already running. If it is, the deployment is skipped.

## Usage

This feature is a foundational component of the declarative stack management system. It is automatically deployed to its own dedicated VM as part of the `phoenix-cli setup` command. The `docker` feature is a prerequisite.