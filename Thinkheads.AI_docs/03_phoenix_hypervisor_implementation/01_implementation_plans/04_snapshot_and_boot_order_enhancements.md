---
title: Snapshot and Boot Order Enhancements
summary: This document outlines the new snapshot and boot order features that have been added to the Phoenix Hypervisor orchestration system.
document_type: Implementation Plan
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Developer
tags:
  - Snapshot
  - Boot Order
  - Orchestration
  - LXC
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Snapshot and Boot Order Enhancements

This document outlines the new snapshot and boot order features that have been added to the Phoenix Hypervisor orchestration system.

## Snapshotting

Two new snapshot features have been implemented to improve the robustness and manageability of the container orchestration process:

*   **"pre-configured" Snapshot:** A snapshot named `pre-configured` is now automatically created for every container immediately before its application script is executed. This snapshot captures the state of the container after all features have been applied but before any application-specific configuration has been run.
*   **"final form" Snapshot:** A snapshot named `final-form` is now automatically created for every container at the end of its orchestration process. This snapshot captures the final, fully configured state of the container.

### Reconfiguration

A new `--reconfigure` flag has been added to the `phoenix_orchestrator.sh` script. This flag allows you to restore a container to its "pre-configured" state and re-run the orchestration from that point.

**Usage:**
```bash
/usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh <CTID> --reconfigure
```

### LetsGo

A new `--LetsGo` flag has been added to the `phoenix_orchestrator.sh` script. This flag provides a streamlined orchestration process that performs the following steps:

1.  **Restores to "pre-configured" state:** The container is reverted to the `pre-configured` snapshot.
2.  **Executes the application script:** The container's application script is run to apply the latest configurations.
3.  **Creates "final-form" snapshot:** A new `final-form` snapshot is created to capture the updated state.
4.  **Starts the container:** The container is automatically started.

This feature is ideal for scenarios where you need to quickly update and restart a container after making changes to its configuration or application code.

**Usage:**
```bash
/usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh <CTID> --LetsGo
```

## Boot Order

The following parameters have been added to the `phoenix_lxc_configs.json` file to control the boot sequence of the containers:

*   `start_at_boot`: A boolean value that determines whether the container should be started at boot time.
*   `boot_order`: An integer that defines the startup order of the containers. Containers with a lower boot order will be started first.
*   `boot_delay`: An integer that specifies the delay in seconds before the container is started.

All containers with an ID of 950 or higher have been configured to start at boot. The boot order and delays have been set based on the dependencies between the containers.

## GPU Container Shutdown

As a final step in the orchestration process, any container with GPU access will be automatically shut down. This is to ensure that VRAM is not unnecessarily consumed by idle containers.