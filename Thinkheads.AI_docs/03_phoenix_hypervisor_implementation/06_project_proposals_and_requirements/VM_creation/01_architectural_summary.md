---
title: "Architectural Summary: VM Integration with Phoenix Hypervisor"
summary: "This document provides an architectural overview of the phoenix_hypervisor and details the integration plan for VM creation capabilities, including dependencies, interfaces, and technical alignment."
document_type: "Architectural Summary"
status: "Implemented"
version: "1.0.0"
author: "Roo"
owner: "Lead Architect"
tags:
  - "Phoenix Hypervisor"
  - "VM Creation"
  - "Architecture"
  - "Integration"
review_cadence: "Ad-hoc"
---

# Architectural Summary: VM Integration with Phoenix Hypervisor

## 1. Overview of Existing Phoenix Hypervisor Architecture

The `phoenix_hypervisor` is a mature, declarative system for managing virtualized infrastructure on Proxmox. Its architecture is defined by the following core principles, which were maintained and extended for VM management:

-   **Declarative Configuration:** A single source of truth for system state is maintained in JSON files (`phoenix_hypervisor_config.json` for global settings, `phoenix_lxc_configs.json` for container specifics).
-   **Idempotent Orchestration:** The central `phoenix` CLI is designed to be stateless and can be run multiple times without causing unintended side effects, ensuring a predictable and resilient workflow.
-   **Modularity:** Functionality is encapsulated in small, single-purpose "feature" scripts, promoting reusability and extensibility.
-   **Hierarchical Templating:** A snapshot-based templating system allows for efficient and consistent creation of new LXC containers.

The orchestration flow for LXC containers is a well-defined state machine that handles creation, configuration, feature installation, and snapshotting.

## 2. Architectural Integration for VM Creation

The integration of VM creation was a natural extension of the existing architecture, designed to provide a completely unified user experience. From the user's perspective, orchestrating a VM is identical to orchestrating an LXC container.

### 2.1. Unified Configuration Strategy

To maintain architectural simplicity and a single source of truth, a new configuration file was not created. Instead, the existing configuration files were enhanced:

-   **`phoenix_hypervisor_config.json`:** This file is the definitive location for all VM definitions. The existing `vms` array was formalized with a comprehensive JSON schema. This centralizes hypervisor-level resources (VMs) in the hypervisor-level configuration. Key properties include:
    -   `vmid`: A unique numeric ID for the VM.
    -   `name`: A unique friendly name for the VM.
    -   `os_type`: (e.g., `ubuntu`, `windows`).
    -   `cores`, `memory_mb`, `disk_size_gb`: Core resource allocation.
    -   `template_image`: The base disk image or ISO to clone from.
    -   `cloud_init`: Configuration for automated setup.
    -   `features`: An array of feature scripts to apply post-creation.
-   **`phoenix_lxc_configs.json`:** This file remains dedicated exclusively to LXC container definitions.

### 2.2. Unified Orchestrator Experience

The `phoenix` CLI was refactored to provide a single, unified command structure for both LXC containers and VMs.

-   **Unified Command:** The user invokes the orchestrator using a single syntax: `phoenix create <ID>`.
-   **Internal Logic Branching:** The `phoenix` dispatcher is responsible for determining the resource type associated with the given `<ID>`. It first checks the `phoenix_lxc_configs.json` for a matching CTID. If not found, it checks the `vms` array in `phoenix_hypervisor_config.json` for a matching `vmid`. Based on the resource type, it then branches its internal logic to call the appropriate manager script (`lxc-manager.sh` or `vm-manager.sh`).

This approach creates a seamless user experience, as illustrated in the revised workflow diagram:

```mermaid
graph TD
    A[Start: phoenix create <ID>] --> B{Is ID an LXC?};
    B -- Yes --> C[Execute LXC State Machine using pct];
    B -- No --> D{Is ID a VM?};
    D -- Yes --> E[Execute VM State Machine using qm];
    D -- No --> F[Error: ID not found];
    C --> G[End];
    E --> G;
    F --> G;
```

### 2.3. Dependencies and Interfaces

-   **Proxmox API / `qm` CLI:** This is the primary interface for all VM lifecycle operations. The `vm-manager.sh` script abstracts the complexities of the `qm` commands.
-   **Cloud-Init:** This is a critical dependency for the automated configuration of new VMs. The `vm-manager.sh` script is responsible for generating and applying the necessary cloud-init configurations.
-   **QEMU Guest Agent:** For post-creation feature application and health checks, the QEMU Guest Agent is the preferred interface.
-   **Storage and Networking:** The VM creation process interfaces directly with the ZFS storage pools and `vmbr0` network bridge defined in `phoenix_hypervisor_config.json`.

### 2.4. Technical Alignment

This integration plan is fully aligned with the technical strategy of the `phoenix_hypervisor` project.

-   **Unified Tooling:** By extending the existing orchestrator, we avoid introducing new tools or workflows.
-   **Declarative Approach:** The reliance on JSON configuration for VMs ensures that the entire system state remains version-controllable and auditable.
-   **Scalability:** The use of templates and a modular feature system for VMs allows the platform to scale to support a large number of diverse virtual machines.

By following this architectural plan, we have seamlessly integrated VM creation capabilities into the Phoenix ecosystem, significantly enhancing its power and flexibility while preserving the elegance and robustness of its original design.