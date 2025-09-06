---
title: "Phoenix Orchestrator Architecture"
tags: ["Phoenix Orchestrator", "Architecture", "LXC", "Container Provisioning", "State Machine", "Configuration Management", "Shell Script"]
summary: "This document outlines the architecture, state machine, configuration, and usage of the `phoenix_orchestrator.sh` script, the cornerstone of the Phoenix Hypervisor project's container provisioning system."
version: "1.0.0"
author: "Phoenix Hypervisor Team"
---

This document outlines the architecture, state machine, configuration, and usage of the `phoenix_orchestrator.sh` script, the cornerstone of the Phoenix Hypervisor project's container provisioning system.

## Overview

The `phoenix_orchestrator.sh` script is the cornerstone of the Phoenix Hypervisor project's container provisioning system. It is designed to be a robust, idempotent, and user-friendly tool for creating and configuring LXC containers based on a declarative JSON configuration. This document outlines its architecture, state machine, configuration, and usage.

## Core Architecture

The orchestrator is built around a state machine and a feature-based customization model. This ensures container provisioning is resumable, predictable, and highly modular.

### Key Components:

-   **State Machine:** The script progresses a container through a series of states: `defined` -> `created` -> `configured` -> `running` -> `customizing` -> `completed`. This ensures that each step of the provisioning process is completed successfully before moving to the next.
-   **Configuration-Driven:** All container specifications are defined in a central JSON file (`phoenix_lxc_configs.json`). This declarative approach separates the "what" from the "how," making the system easier to manage and scale.
-   **Feature-Based Customization:** After a container is running, the orchestrator applies a series of modular "feature" scripts based on a `features` array in the configuration. This allows for a compositional approach to building containers.
-   **Application Runner:** For containers that run persistent services, an optional `application_script` can be defined. This script is executed after all features are applied to launch the final application.
-   **Idempotency:** Rerunning the script for a container that is already fully provisioned will result in no changes.
-   **Logging:** Comprehensive logging provides a clear audit trail of the script's execution.
-   **Dry-Run Mode:** A `--dry-run` flag allows for safe validation of the configuration and script logic without making any actual changes to the system.

## Dual-Mode Operation

The orchestrator now operates in two primary modes:

-   **Hypervisor Setup (`--setup-hypervisor`)**: This mode is responsible for the initial configuration of the Proxmox host itself. It reads its configuration from `hypervisor_config.json` and executes a series of modular scripts to set up storage, networking, users, and other system-level features.
-   **LXC Provisioning**: This is the original mode of operation, which focuses on creating and configuring LXC containers based on definitions in `phoenix_lxc_configs.json`.

This unified approach allows the `phoenix_orchestrator.sh` script to be the single entry point for the entire lifecycle of the hypervisor and its containers.

## The State Machine

The state of each container is stored in `/var/lib/phoenix_hypervisor/state/<CTID>.state`. The script transitions the container through the following states:

1.  **`defined`**: The initial state. The container is defined in the configuration but does not yet exist. The orchestrator will either create or clone the container.
2.  **`created`**: The container exists but is not yet configured. The orchestrator will apply settings like memory, CPU, and network.
3.  **`configured`**: The container is configured but not running. The orchestrator will start the container.
4.  **`running`**: The container is running. The orchestrator will proceed to the customization phase.
5.  **`customizing`**: The orchestrator executes all feature scripts defined in the container's `features` array.
6.  **`completed`**: The final state. All features and application scripts have been executed.

## Configuration File Format

The orchestrator relies on the `phoenix_lxc_configs.json` file for all container definitions.

```json
{
  "lxc_configs": {
    "950": {
      "name": "vllmQwen3Coder",
      "clone_from_ctid": "920",
      "memory_mb": 40960,
      "cores": 8,
      "features": [
        "base_setup",
        "nvidia",
        "docker",
        "vllm"
      ],
      "application_script": "phoenix_hypervisor_lxc_950.sh"
    }
  }
}
```

## How to Use the Script

### Hypervisor Setup

To perform the initial, idempotent setup of the hypervisor, use the `--setup-hypervisor` flag. The script will read its configuration from `etc/hypervisor_config.json` and apply all system-level settings.

```bash
./phoenix_orchestrator.sh --setup-hypervisor
```

### LXC Container Provisioning

To provision a container, simply run the script with the container's ID (CTID) as an argument:

```bash
./phoenix_orchestrator.sh 950
```

### Dry-Run Mode

To see what actions the script *would* take without actually executing them, use the `--dry-run` flag:

```bash
./phoenix_orchestrator.sh 950 --dry-run
```

### Logging

All actions are logged to `/var/log/phoenix_hypervisor/orchestrator_YYYYMMDD.log`.