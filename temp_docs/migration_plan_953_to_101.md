# Migration Plan: Transitioning from Container 953 to 101

## 1. Executive Summary

This document outlines the comprehensive plan to migrate the Nginx gateway functionality from the legacy container `953` to the new, declaratively configured container `101`. The core of this migration involves enhancing the Phoenix Hypervisor's orchestration capabilities to align with its "Configuration as Code" principles, ensuring that container `101` is a robust and maintainable replacement.

The key architectural change is the introduction of a declarative volume mounting system for LXC containers, which mirrors the existing strategy for VMs. This will allow container `101` to be configured using centrally managed files, eliminating the need for container-specific configuration logic.

## 2. Architectural Overview

The following diagram illustrates the enhanced architecture, where the `lxc-manager.sh` script now reads container-specific `mount_points` from `phoenix_lxc_configs.json` to configure the container.

```mermaid
graph TD
    subgraph "Guest Configuration"
        A[phoenix_lxc_configs.json <br> .lxc_configs.[101].mount_points]
    end

    subgraph "Orchestration"
        C{lxc-manager.sh}
    end

    subgraph "Guest Instance"
        E[LXC Container 101]
    end

    A -- "Defines host paths" --> C;
    C -- "pct set --mpX ..." --> E;
```

## 3. Implementation Todo List for `code` mode

The following is a clear, actionable todo list for the `code` mode to execute. All necessary code and configuration changes are detailed in the `temp_docs/implementation_plan.md` document.

- [ ] **Modify `lxc-manager.sh`**:
    - [ ] Add the new `apply_mount_points` function to `usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh`.
    - [ ] Integrate the `apply_mount_points` function into the `main_lxc_orchestrator` workflow.

- [ ] **Update `phoenix_lxc_configs.json`**:
    - [ ] Add the `mount_points` array to the configuration for container `101` in `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`.

- [ ] **Revise `phoenix_hypervisor_lxc_101.sh`**:
    - [ ] Replace the contents of `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh` with the revised script that uses the mounted configurations.

- [ ] **Final Validation**:
    - [ ] After the changes are applied, run `phoenix create 101` to re-provision the container with the new configuration.
    - [ ] Verify that the Nginx service is running correctly and that all backend services are accessible through the gateway.

## 4. Supporting Documentation

*   **Architectural Proposal**: `temp_docs/lxc_shared_volume_proposal.md`
*   **Detailed Implementation Plan**: `temp_docs/implementation_plan.md`

This migration plan provides a clear path to modernizing the Nginx gateway configuration, improving the maintainability and scalability of the Phoenix Hypervisor ecosystem.