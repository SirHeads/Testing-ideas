---
title: "Roadmap: Staged Enhancements for VM Creation"
summary: "This document outlines the phased roadmap for integrating VM creation into the phoenix_orchestrator, including timelines, milestones, and dependencies."
document_type: "Roadmap"
status: "Draft"
version: "1.0.0"
author: "Roo"
owner: "Project Lead"
tags:
  - "Phoenix Hypervisor"
  - "VM Creation"
  - "Roadmap"
  - "Phased Rollout"
review_cadence: "Ad-hoc"
---

# Roadmap: Staged Enhancements for VM Creation

## 1. Guiding Principles

This roadmap is designed to be iterative and incremental, ensuring that we deliver value at each stage while managing complexity. The core principles are:

-   **Start Simple:** Begin with a minimal viable product (MVP) to validate the core functionality.
-   **Build Incrementally:** Each phase will build upon the success of the previous one.
-   **User Feedback:** Incorporate user feedback at each stage to ensure the solution meets real-world needs.
-   **Maintain Architectural Integrity:** Adhere to the established principles of the `phoenix_hypervisor` ecosystem.

## 2. Phased Rollout

### Phase 1: Foundational VM Lifecycle Management (MVP)

-   **Timeline:** 2 Weeks
-   **Objective:** Implement the basic lifecycle operations for a single, well-defined VM.
-   **Key Milestones:**
    1.  **Schema Definition:** Finalize and implement the JSON schema for the `vms` array within `phoenix_hypervisor_config.json`.
    2.  **Unified Orchestrator Logic:** Refactor `phoenix_orchestrator.sh` to accept a generic `<ID>` and implement the internal branching logic to differentiate between LXC and VM orchestration. Deprecate the `--create-vm` and other VM-specific flags.
    3.  **Core `qm` Integration:** Implement the core `qm create`, `qm set`, `qm start`, `qm stop`, and `qm destroy` commands within the new VM branch of the orchestrator.
    4.  **Basic Cloud-Init:** Implement a simple, static Cloud-Init configuration to set a hostname and user account.
    5.  **End-to-End Test:** Successfully create and destroy a standard Ubuntu 24.04 server VM from a pre-existing template image.
-   **Dependencies:**
    -   A base Ubuntu 24.04 VM template with the QEMU Guest Agent installed must be available on the Proxmox host.

### Phase 2: Advanced Configuration and Templating

-   **Timeline:** 3 Weeks
-   **Objective:** Introduce dynamic configuration, templating, and a feature installation framework for VMs.
-   **Key Milestones:**
    1.  **Dynamic Cloud-Init:** Implement logic to dynamically generate Cloud-Init configurations based on the VM's JSON definition (e.g., network settings, user SSH keys).
    2.  **VM Templating:** Create a mechanism to designate a VM as a "template" and create snapshots, similar to the LXC `template_snapshot_name` feature.
    3.  **Feature Script Framework:** Develop a framework for executing feature scripts inside the VM, likely using the QEMU Guest Agent (`qm guest exec`).
    4.  **Initial Feature Script:** Create a `feature_install_docker.sh` script as a proof-of-concept for the new framework.
    5.  **End-to-End Test:** Provision a new Ubuntu 24.04 VM, apply the Docker feature, and verify that Docker is running correctly.
-   **Dependencies:**
    -   Completion of all Phase 1 milestones.

### Phase 3: Full Integration and User Enablement

-   **Timeline:** 2 Weeks
-   **Objective:** Fully integrate VM management into the broader Phoenix ecosystem and provide comprehensive user documentation.
-   **Key Milestones:**
    1.  **Health Checks:** Implement a health check mechanism for VMs, using the QEMU Guest Agent to verify service status.
    2.  **Shared Volume Mounting:** Investigate and implement a strategy for mounting shared ZFS datasets into VMs (e.g., via NFS or Samba, managed by the orchestrator).
    3.  **Documentation:** Create a comprehensive guide for defining, creating, and managing VMs within the `Thinkheads.AI_docs`.
    4.  **User Acceptance Testing (UAT):** Conduct UAT with the target users to provision the four required Ubuntu VMs with Docker.
-   **Dependencies:**
    -   Completion of all Phase 2 milestones.

## 3. Future Enhancements (Post-MVP)

The following capabilities are considered out of scope for the initial implementation but represent potential future enhancements:

-   **Multi-OS Support:** Develop and test templates for other operating systems (e.g., CentOS, Windows).
-   **GPU Passthrough:** Implement automated configuration for passing through NVIDIA GPUs to VMs.
-   **Automated Networking:** Integrate with network management tools to automate IP address allocation.
-   **Live Migrations:** Explore and potentially implement support for live VM migrations between Proxmox nodes.