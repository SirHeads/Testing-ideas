---
title: "Project Proposal & Strategic Business Case: VM Creation in Phoenix Orchestrator"
summary: "This document outlines the strategic business case, objectives, benefits, risks, and justification for integrating Virtual Machine (VM) creation capabilities into the phoenix_orchestrator system."
document_type: "Project Proposal"
status: "Draft"
version: "1.0.0"
author: "Roo"
owner: "Project Lead"
tags:
  - "Phoenix Hypervisor"
  - "VM Creation"
  - "Strategy"
  - "Business Case"
review_cadence: "Ad-hoc"
---

# Project Proposal & Strategic Business Case: VM Creation in Phoenix Orchestrator

## 1. Executive Summary

This document proposes the integration of full lifecycle management for Virtual Machines (VMs) into the `phoenix_orchestrator` system. Building upon the success and architectural principles of the existing LXC container management, this initiative will extend the platform's capabilities to support a broader range of workloads, particularly those requiring full hardware virtualization and OS isolation. The initial goal is to provision a standard Ubuntu 24.04 server VM, with a long-term vision of supporting multiple, complex, Docker-enabled environments. This project aligns directly with Thinkheads.AI's strategic objective to create a robust, flexible, and scalable infrastructure for advanced AI/ML development and deployment.

## 2. Strategic Business Case

### 2.1. Problem Statement

The current `phoenix_orchestrator` exclusively supports LXC containers. While efficient for many use cases, LXC's OS-level virtualization is insufficient for scenarios requiring:
- **Kernel-level Isolation:** Running different operating systems or kernel versions than the host.
- **Enhanced Security:** Workloads that demand stronger security boundaries than containers can provide.
- **Complex Networking:** Environments that require unique or complex network stacks that are difficult to configure with LXC.
- **Legacy Applications:** Applications that are not container-native or have specific OS dependencies.

The immediate need to support multiple Ubuntu VMs running Docker for containerized services highlights a critical gap in our current infrastructure capabilities.

### 2.2. Proposed Solution

We propose to extend the `phoenix_orchestrator` to manage the complete lifecycle of QEMU/KVM virtual machines. This will be achieved by enhancing the existing declarative, idempotent, and modular architecture. The orchestrator will leverage the `qm` command-line tool in Proxmox and be driven by extended JSON configurations, mirroring the successful pattern established for LXC management.

### 2.3. Objectives

- **Primary Objective:** Enable `phoenix_orchestrator` to create, configure, start, stop, and delete QEMU/KVM virtual machines based on declarative JSON definitions.
- **Initial Milestone:** Successfully provision a basic Ubuntu 24.04 server VM.
- **Secondary Objective:** Establish a scalable framework for VM templating and feature application, similar to the existing LXC implementation.
- **Business Goal:** Increase infrastructure flexibility, support a wider range of development and deployment scenarios, and enhance the security posture for sensitive workloads.

### 2.4. Benefits

- **Increased Flexibility:** Support for any operating system, enabling a much broader set of applications and development environments.
- **Enhanced Security:** Full hardware virtualization provides superior isolation between workloads and the host system.
- **Unified Orchestration:** Manage both containers and VMs through a single, consistent interface (`phoenix_orchestrator.sh`), reducing operational complexity.
- **Future-Proofing:** Positions the Phoenix platform to handle future projects that may have requirements incompatible with containerization.
- **Alignment with Industry Standards:** KVM is a mature, industry-standard hypervisor, ensuring stability and a wide support base.

## 3. Risk Analysis

| Risk Category | Risk Description | Likelihood | Impact | Mitigation Strategy |
| :--- | :--- | :--- | :--- | :--- |
| **Technical** | Complexity of VM lifecycle management (storage, networking, devices) compared to LXC. | Medium | Medium | Leverage existing Proxmox `qm` tool abstractions. Start with a simple, well-defined target (Ubuntu 24.04 server). |
| **Technical** | Performance overhead of VMs compared to LXC containers. | High | Low | Acknowledge performance difference as a trade-off for isolation. Optimize VM configurations for specific workloads. |
| **Project** | Scope creep; attempting to support too many OS types or complex features too early. | Medium | High | Adhere to a phased roadmap, starting with a minimal viable product (MVP). Gain user approval for each phase. |
| **Operational** | Increased resource consumption (CPU, RAM, disk space) on the hypervisor. | High | Medium | Implement resource monitoring and capacity planning. Define clear resource allocation guidelines in the VM configuration schema. |

## 4. Justification and Strategic Alignment

The Phoenix Hypervisor is the cornerstone of Thinkheads.AI's compute strategy. Integrating VM creation is not merely an incremental feature; it is a strategic enhancement that elevates the platform to a true, general-purpose hypervisor management system. It directly supports the company's goals by:

- **Enabling Advanced AI/ML Workloads:** Providing isolated, powerful environments for development, testing, and production, as outlined in the `thinkheadsAI_environment_requirements.md`.
- **Strengthening Architectural Principles:** Extending the successful declarative and modular design of the `phoenix_hypervisor` to a new resource type, reinforcing our commitment to Infrastructure-as-Code.
- **Unlocking New Opportunities:** Allowing the platform to host a wider variety of projects and third-party tools without the constraints of containerization.

This project is a logical and necessary evolution of the Phoenix platform, ensuring it remains a robust and versatile foundation for all future technical endeavors at Thinkheads.AI.