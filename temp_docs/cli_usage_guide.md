---
title: Phoenix Hypervisor CLI Usage Guide
summary: This document provides a comprehensive guide to the phoenix-cli, the primary command-line interface for managing the Phoenix Hypervisor environment.
document_type: Implementation Guide
status: Final
version: "1.0.0"
author: Roo
owner: Developer
tags:
  - Phoenix Hypervisor
  - CLI
  - Orchestration
  - Usage Guide
review_cadence: Annual
last_reviewed: "2025-10-20"
---

# Phoenix Hypervisor CLI Usage Guide

The `phoenix-cli` is the primary command-line interface for managing the entire Phoenix Hypervisor environment. It provides a simple, verb-based interface for orchestrating the lifecycle of all guests (VMs and LXCs) and services.

## Synopsis
`phoenix <verb> [targets...] [options...]`

## Core Concepts
-   **Declarative Configuration**: The CLI reads its desired state from a set of JSON files located in `/usr/local/phoenix_hypervisor/etc/`. All operations aim to make the live system match the state defined in these files.
-   **Idempotency**: Commands can be run multiple times without changing the result beyond the initial application. For example, running `phoenix create 101` twice will only create the guest on the first run.
-   **Dependency Resolution**: The CLI automatically understands the relationships between guests. When you ask to `create` a guest, it will first ensure all of its dependencies (including templates) are created in the correct order.

---
## Verbs

### `setup`
Initializes or reconfigures the hypervisor environment itself. This command operates on the Proxmox host, not on individual guests.

**Usage:**
`phoenix setup [options...]`

**Description:**
The `setup` command reads the `phoenix_hypervisor_config.json` file and applies host-level configurations, such as creating ZFS pools, configuring networking, setting up firewall rules, and installing host-level services.

---
### `create`
Creates one or more guests (VMs or LXCs) if they do not already exist.

**Usage:**
`phoenix create <guest_id> [guest_id...]`

**Description:**
The `create` verb provisions a new guest by resolving its dependencies, creating it from the appropriate template if it doesn't exist, applying all defined configurations, and running its feature installation scripts.

---
### `converge`
Ensures one or more guests exist and forcefully re-applies all configurations and features.

**Usage:**
`phoenix converge <guest_id> [guest_id...]`

**Description:**
`converge` is a powerful command that brings a guest and its entire dependency chain into perfect alignment with the configuration files by re-running the full configuration and feature application process for each guest in the chain.

---
### `delete`
Deletes one or more guests.

**Usage:**
`phoenix delete <guest_id> [guest_id...]`

**Description:**
This command stops and permanently deletes the specified guest(s). It does not resolve dependencies and only acts on the explicitly listed targets.

---
### `start`, `stop`, `restart`, `status`
Standard lifecycle commands for managing the state of guests.

**Usage:**
`phoenix start <guest_id>`

**Description:**
These commands perform the expected action. `start` will resolve dependencies to ensure they are started in the correct order.

---
### `sync`
Synchronizes Portainer environments and Docker stacks.

**Usage:**
`phoenix sync <target>`

**Description:**
This command connects to the Portainer API to ensure that Docker environments and stacks are configured as defined in `phoenix_stacks_config.json`.

---
### `LetsGo`
The master command to create and start the entire environment from scratch.

**Usage:**
`phoenix LetsGo`

**Description:**
This command orchestrates the creation and startup of every guest defined in the configuration files, creating them in dependency order, starting them in boot order, and finishing with a full Portainer sync.