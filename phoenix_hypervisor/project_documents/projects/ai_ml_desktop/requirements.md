---
title: "Project Requirements for AI/ML Desktop Environment"
tags: ["AI/ML", "Desktop Environment", "LXC", "Proxmox", "Hardware Requirements", "Software Requirements", "Network Requirements", "NVIDIA GPU", "RustDesk", "CUDA", "TensorFlow", "PyTorch", "Jupyter"]
summary: "This document details the hardware, software, and configuration requirements for the AI/ML Desktop Environment project, including host system specifications, necessary software, and network configurations."
version: "1.0.0"
author: "Phoenix Hypervisor Team"
---

This document details the hardware, software, and configuration requirements for the AI/ML Desktop Environment project.

## Hardware Prerequisites
- **Host System:** A server running Proxmox 9.
- **CPU:** 16+ cores recommended.
- **RAM:** 64GB+ recommended.
- **Storage:** NVMe or SSD for fast disk access.
- **GPU:** Two NVIDIA 5060 Ti 16GB GPUs.

## Software Prerequisites
- **Proxmox Templates:** Ubuntu 24.04 or Debian 12.
- **NVIDIA Drivers:** Latest version (e.g., 560 series) installed on the Proxmox host.
- **LXC Container:** Unprivileged container for security.
- **Desktop Environment:** A lightweight DE such as XFCE or MATE.
- **Remote Access:** A self-hosted RustDesk server and the RustDesk client installed in the container.
- **AI/ML Stack:** CUDA Toolkit, TensorFlow, PyTorch, and Jupyter Notebooks.

## Network Requirements
- **Network Bridge:** A Proxmox bridge (e.g., vmbr0) for container networking.
- **Firewall Rules:** Ports 21115-21117 must be open for RustDesk communication.