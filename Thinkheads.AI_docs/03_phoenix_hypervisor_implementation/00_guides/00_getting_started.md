---
title: "Getting Started Guide"
summary: "A guide for new developers, outlining how to set up their environment, clone the repository, and run the orchestrator for the first time."
document_type: "Implementation Guide"
status: "Published"
version: "2.0.0"
author: "Thinkheads.AI"
owner: "Developer"
tags:
  - "Getting Started"
  - "Development Environment"
  - "Onboarding"
review_cadence: "Annual"
last_reviewed: "2025-09-29"
---

# Getting Started Guide

This document provides instructions for new developers on how to set up their environment, clone the repository, and run the orchestrator for the first time.

## 1. Introduction to the Declarative Architecture

The Phoenix Hypervisor uses a declarative architecture, where the desired state of the entire system—including Virtual Machines (VMs) and LXC containers—is defined in JSON configuration files. The `phoenix_orchestrator.sh` script reads these configurations and makes the necessary changes to the Proxmox environment to match the desired state. This approach ensures that the system is predictable, repeatable, and easy to manage.

## 2. Setting Up Your Environment

Before you can start working with the Phoenix Hypervisor, you need to set up your development environment.

### Prerequisites

*   A Proxmox VE 7.x or later host
*   A user with sudo privileges on the Proxmox host
*   Git and `jq` installed on the Proxmox host

### Cloning the Repository

Clone the `phoenix_hypervisor` repository to your Proxmox host:

```bash
git clone https://github.com/thinkheads-ai/phoenix_hypervisor.git /usr/local/phoenix_hypervisor
```

## 3. Running the Orchestrator

The `phoenix_orchestrator.sh` script is the single entry point for managing the Phoenix Hypervisor. It is located in the `bin` directory of the repository.

### Initial Setup

Before you can create any containers or VMs, you need to run the initial setup command to configure the Proxmox host:

```bash
/usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh --setup-hypervisor
```

This command will install the necessary dependencies, configure the network, and set up the ZFS storage pools.

### Creating a VM or LXC Container

To create a new VM or LXC container, you first need to define its configuration in the appropriate JSON file:
*   **For VMs:** `usr/local/phoenix_hypervisor/etc/phoenix_vm_configs.json`
*   **For LXC Containers:** `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`

Once you have defined the resource, you can create it by running the following unified command:

```bash
/usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh <ID>
```

Where `<ID>` is the `vmid` or `ctid` of the resource you want to create or update. The orchestrator will automatically determine the resource type based on the configuration files.

## 4. Further Reading

For more detailed information about the system architecture and specific container implementations, please refer to the following guides:
*   [System Architecture Guide](00_system_architecture_guide.md)
*   [LXC Container Implementation Guide](02_lxc_container_implementation_guide.md)