---
title: Architectural Principles
summary: This document outlines the architectural principles for Thinkheads.AI, including modularity, reusability, idempotency, declarative configuration, configuration as code, security by design, and an open-source-first approach.
document_type: Technical Strategy
status: Approved
version: 2.0.0
author: Thinkheads.AI
owner: Technical VP
tags:
  - Architectural Principles
  - Strategy
  - Technical
  - Architecture
  - Modularity
  - Idempotency
  - Declarative Configuration
  - Configuration as Code
  - Security by Design
  - Open Source
review_cadence: Bi-Annually
last_reviewed: 2025-09-29
---
# Architectural Principles

The architectural principles guiding ThinkHeads.ai's technical strategy ensure a robust, efficient, and maintainable platform for AI/ML/DL development and deployment. These principles are derived from the operational and technological choices made across the project, and they serve as the foundation for all future development.

## Modularity and Reusability
*   **Principle**: Components are designed as independent, interchangeable modules that can be easily integrated and reused across different parts of the system.
*   **Application**: Achieved through a sophisticated templating system for LXC containers and VMs. Base templates are created with common features (e.g., `base_setup`, `nvidia`, `docker`), and then cloned to create more specialized containers. This is defined in the `phoenix_lxc_configs.json` file, where containers can be configured with a `clone_from_ctid` and a `features` array. This promotes a clear separation of concerns, simplifies maintenance, and allows for rapid provisioning of new services.

## Idempotency
*   **Principle**: Operations and deployments are designed to produce the same result regardless of how many times they are executed, ensuring consistency and reliability.
*   **Application**: Supported by the declarative nature of the configuration files and the state-checking logic in the `phoenix_orchestrator.sh` script. The orchestrator ensures that the actual state of the infrastructure matches the desired state defined in the JSON configuration files. This minimizes configuration drift and ensures that the system is always in a predictable state. The use of snapshots for creating templates also contributes to idempotency by providing a consistent starting point for new containers and VMs.

## Declarative Configuration
*   **Principle**: The desired state of the system is defined in a declarative manner, and the system is responsible for achieving that state.
*   **Application**: The entire infrastructure, from ZFS pools and datasets to LXC containers and VMs, is defined in the `phoenix_hypervisor_config.json`, `phoenix_lxc_configs.json`, and `phoenix_vm_configs.json` files. The `phoenix_orchestrator.sh` script reads these files and takes the necessary actions to bring the system into the desired state. This approach simplifies management, reduces the risk of human error, and makes the system more predictable and auditable.

## Configuration as Code
*   **Principle**: Infrastructure and application configurations are managed as version-controlled code, enabling automated provisioning, consistent environments, and clear audit trails.
*   **Application**: The use of JSON configuration files, combined with JSON schema files for validation (`phoenix_hypervisor_config.schema.json`, `phoenix_lxc_configs.schema.json`), ensures that the entire system configuration is treated as code. This allows for versioning, automated testing, and a clear history of all changes. The `phoenix_orchestrator.sh` script acts as the engine that consumes these configurations, making the entire system reproducible and manageable programmatically.

## Security by Design
*   **Principle**: Security is integrated into the architecture from the ground up, rather than being an afterthought.
*   **Application**: The project incorporates several security features, including the use of AppArmor profiles for containers, unprivileged containers by default, and firewall rules defined in the configuration files. The `apparmor_profile` and `firewall` sections in the `phoenix_lxc_configs.json` file allow for fine-grained control over container security. This approach ensures that security is a core part of the infrastructure and not just a layer on top.

## Open-Source First
*   **Principle**: Prioritize the adoption and integration of free and open-source software solutions to minimize costs, foster community collaboration, and leverage a vast ecosystem of tools and innovations. Proprietary solutions are acceptable if they are industry standards or provide a distinct, unique advantage (e.g., NVIDIA drivers for GPU acceleration).
*   **Application**: A cornerstone of the ThinkHeads.ai project, driven by a zero-revenue model and a commitment to cost-efficiency. Key technologies like Proxmox, Ollama, FastAPI, n8n, PostgreSQL, Nginx, Qdrant, and vLLM are all open-source, enabling powerful capabilities without significant financial investment. The project itself is licensed under the MIT License, further reinforcing the commitment to open source.
