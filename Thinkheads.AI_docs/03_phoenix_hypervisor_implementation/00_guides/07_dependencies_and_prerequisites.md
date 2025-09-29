---
title: Dependencies and Prerequisites
summary: This document lists all the external dependencies and prerequisites for setting up and running the Phoenix Hypervisor.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Dependencies
- Prerequisites
- Phoenix Hypervisor
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Dependencies and Prerequisites

This document lists all the external dependencies and prerequisites for setting up and running the Phoenix Hypervisor.

## Hardware

*   **Proxmox Host**: A physical server with Proxmox VE 7.x or later installed.
*   **CPU**: A modern multi-core CPU (AMD or Intel).
*   **Memory**: A minimum of 16 GB of RAM.
*   **Storage**: A fast storage device, such as an SSD or NVMe drive.
*   **GPU**: An NVIDIA GPU is required for GPU passthrough and vLLM support.

## Software

*   **Proxmox VE**: Version 7.x or later.
*   **Git**: For cloning the Phoenix Hypervisor repository.
*   **jq**: For parsing JSON in the shell scripts.
*   **NVIDIA Drivers**: The appropriate NVIDIA drivers for your GPU.
*   **Docker**: For running containerized applications.
*   **Python**: For running the vLLM and other Python-based tools.

## Network

*   **Internet Access**: The Proxmox host must have access to the internet to download packages and container images.
*   **Static IP Address**: It is recommended to assign a static IP address to the Proxmox host.
*   **Firewall**: The firewall on the Proxmox host must be configured to allow access to the necessary ports.

## Virtual Machine Template Dependencies

*   **qemu-guest-agent**: All base VM templates **MUST** have the `qemu-guest-agent` installed and enabled to ensure proper communication with the `phoenix_orchestrator`.