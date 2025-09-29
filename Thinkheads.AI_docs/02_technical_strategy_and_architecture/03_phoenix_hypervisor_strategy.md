---
title: Phoenix Hypervisor Strategy
summary: This document outlines the strategic importance and configuration of the Phoenix Hypervisor, the central powerhouse for Thinkheads.AI's compute-intensive AI/ML/DL workloads.
document_type: Technical Strategy
status: Approved
version: 2.0.0
author: Thinkheads.AI
owner: Technical VP
tags:
  - Phoenix Hypervisor
  - Strategy
  - Technical
  - Architecture
  - Proxmox
  - LXC
  - VM
  - GPU
  - AppArmor
  - Docker
review_cadence: Quarterly
last_reviewed: 2025-09-29
---
# Phoenix Hypervisor Strategy

The local Proxmox server, codenamed "Phoenix Hypervisor," serves as the central powerhouse for ThinkHeads.ai's compute-intensive AI/ML/DL workloads, orchestrating both LXC containers and Virtual Machines (VMs). Its strategic configuration and resource management are critical for supporting the project's ambitious goals in skill development and portfolio creation.

## Hardware Specifications
*   **CPU**: AMD 7700
*   **RAM**: 96 GB DDR5
*   **GPUs**: Dual RTX 5060 Ti
*   **Storage**: NVMe

## Central Role and Workloads
The Phoenix Hypervisor is specifically designed to host and manage demanding AI tasks, including:
*   **LLM Training and Inference**: Running large language models (LLMs) via vLLM and Ollama for the AI-driven website, Learning Assistant, and Meeting Room sub-products.
*   **Image Processing**: Handling AI-powered image generation and manipulation tasks, such as avatar creation for User Profiles using Imagen (or equivalent AI image model).
*   **Development Environments**: Providing isolated and powerful environments for interactive ML desktop development through both LXC containers and Virtual Machines (VMs) with GPU passthrough.

## Configuration and Resource Management
The Proxmox VE virtualization platform is configured to optimize resource utilization and ensure efficient operation across both LXC containers and Virtual Machines (VMs):
*   **LXC Containers**:
    *   `lxc-955`: Dedicated for LLM hosting with one RTX 5060 Ti GPU passthrough.
    *   `lxc-956`: Configured for image processing, PostgreSQL, and dynamic GPU access, allowing flexible allocation of the second RTX 5060 Ti.
    *   `lxc-957`: Used for testing and experimentation of new features and models.
*   **VM with GPU Passthrough**: A dedicated virtual machine provides an interactive ML desktop environment, leveraging direct GPU access for intensive development and debugging.
*   **GPU Scheduling**: Careful scheduling and dynamic release mechanisms are implemented to manage the dual RTX 5060 Ti GPUs, preventing clashes between concurrent LLM and image processing tasks and ensuring optimal performance for each workload.
*   **Network and Remote Access**: A shared network facilitates internal communication, while SSH access and RustDesk enable secure remote management and monitoring of the hypervisor and its hosted services.
*   **Unified AppArmor Nesting**: A unified AppArmor nesting strategy is employed to provide strong security boundaries for nested containers, particularly for the Docker-LXC integration.
*   **Docker-LXC Integration**: Docker is seamlessly integrated into the LXC containers, allowing for the deployment of containerized applications within the Phoenix Hypervisor ecosystem.

## Strategic Importance
The Phoenix Hypervisor's robust capabilities and flexible configuration are paramount to ThinkHeads.ai's success, enabling the execution of complex AI/ML/DL projects within defined resource constraints and supporting the rapid iteration and deployment of AI applications. Its ability to efficiently manage GPU-intensive tasks is a key enabler for achieving high-impact portfolio pieces.
