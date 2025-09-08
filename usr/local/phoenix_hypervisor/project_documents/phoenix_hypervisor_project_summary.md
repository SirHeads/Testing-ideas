---
title: Phoenix Hypervisor Project Summary
summary: This document provides a summary of the Phoenix Hypervisor project, outlining
  its goals, capabilities, and core architectural concepts for orchestrating LXC containers and Virtual Machines (VMs)
  tailored for AI and machine learning workloads on Proxmox.
document_type: Strategy | Technical | Business Case | Report
status: Draft | In Review | Approved | Archived
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Team/Individual Name
tags:
- Phoenix Hypervisor
- Project Summary
- LXC
- VMs
- Container Orchestration
- AI Workloads
- Machine Learning
- Proxmox
- Declarative Configuration
- State Machine
- Feature-Based Customization
review_cadence: Annual | Quarterly | Monthly | None
last_reviewed: YYYY-MM-DD
---
This document provides a summary of the Phoenix Hypervisor project's goals, capabilities, and a post-implementation review of issues and suggested improvements from the initial build phase.

## Overview

The Phoenix Hypervisor project provides a robust, declarative, and feature-based system for orchestrating the creation and configuration of LXC containers and Virtual Machines (VMs), specifically tailored for AI and machine learning workloads on Proxmox.

The core of the project is the `phoenix_orchestrator.sh` script, a single, idempotent orchestrator that manages the entire lifecycle of a container based on a central JSON configuration file.

## Key Architectural Concepts

-   **Declarative Configuration:** All container specifications are defined in `phoenix_lxc_configs.json`. This allows for a clear and manageable definition of the desired state of each container.
-   **State Machine:** The orchestrator uses a state machine (`defined` -> `created` -> `configured` -> `running` -> `customizing` -> `completed`) to ensure that container provisioning is resumable and predictable.
-   **Feature-Based Customization:** Container customization is handled through a series of modular, reusable "feature" scripts. These scripts (e.g., for installing NVIDIA drivers, Docker, or vLLM) are applied compositionally based on a `features` array in the container's configuration.
-   **Hybrid Application Model:** While foundational setup is handled by features, the system supports an optional `application_script` for launching persistent services (like a vLLM server) in the final application container.

## Core Components

-   **Orchestrator (`phoenix_orchestrator.sh`):** The single point of entry for all container provisioning.
-   **Configuration (`phoenix_lxc_configs.json`):** The "blueprint" for all containers.
-   **Feature Scripts (`phoenix_hypervisor_feature_*.sh`):** Modular scripts that provide specific functionalities.
-   **Application Runners (`phoenix_hypervisor_lxc_*.sh`):** Optional scripts for launching persistent services.

This architecture provides a powerful, flexible, and maintainable platform for managing complex AI-focused LXC and VM environments.
