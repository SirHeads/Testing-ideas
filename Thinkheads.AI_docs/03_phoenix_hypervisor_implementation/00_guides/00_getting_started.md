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

The Phoenix Hypervisor has transitioned to a declarative architecture, where the desired state of the system is defined in configuration files. The `phoenix_orchestrator.sh` script reads these configurations and makes the necessary changes to the Proxmox environment to match the desired state. This approach ensures that the system is predictable, repeatable, and easy to manage.

## 2. Setting Up Your Environment

Before you can start working with the Phoenix Hypervisor, you need to set up your development environment.

### Prerequisites

*   A Proxmox VE 7.x or later host
*   A user with sudo privileges on the Proxmox host
*   Access to the Proxmox API
*   Git installed on your local machine

### Cloning the Repository

Clone the `phoenix_hypervisor` repository to your local machine:

```bash
git clone https://github.com/thinkheads-ai/phoenix_hypervisor.git
```

## 3. Running the Orchestrator

The `phoenix_orchestrator.sh` script is the main entry point for managing the Phoenix Hypervisor. It is located in the `bin` directory of the repository.

### Initial Setup

Before you can create any containers or VMs, you need to run the initial setup command to configure the Proxmox host:

```bash
./phoenix_orchestrator.sh --setup-hypervisor
```

This command will install the necessary dependencies, configure the network, and set up the storage.

### Creating a Container

To create a new container, you need to define its configuration in the `phoenix_lxc_configs.json` file. Once you have defined the container, you can create it by running the following command:

```bash
./phoenix_orchestrator.sh CTID
```

Where `CTID` is the ID of the container you want to create.

## 4. Refactored LXC Container Management

The LXC container management scripts have been refactored to be more modular and easier to maintain. The new scripts are located in the `bin/lxc_setup` directory. Each script is responsible for a specific feature, such as installing Docker or configuring the network.

For more information about the refactored scripts, please refer to the [LXC Container Implementation Guide](02_lxc_container_implementation_guide.md).