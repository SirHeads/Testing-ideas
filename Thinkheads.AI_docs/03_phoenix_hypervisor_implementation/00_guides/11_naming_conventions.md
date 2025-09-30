---
title: "Naming Conventions"
summary: "This document defines the naming conventions for scripts, configuration files, and other assets within the Phoenix Hypervisor project."
document_type: "Implementation Guide"
status: "Published"
version: "1.0.0"
author: "Thinkheads.AI"
owner: "Developer"
tags:
  - "Naming Conventions"
  - "Style Guide"
review_cadence: "Annual"
last_reviewed: "2025-09-29"
---

# Naming Conventions

This document defines the naming conventions for scripts, configuration files, and other assets within the Phoenix Hypervisor project.

## 1. Scripts

All scripts in the `bin` directory should be prefixed with `phoenix_hypervisor_`. The rest of the script name should be in lowercase with words separated by underscores.

*   **Example:** `phoenix_hypervisor_lxc_952.sh`

## 2. Configuration Files

All configuration files in the `etc` directory should be prefixed with `phoenix_`. The rest of the file name should be in lowercase with words separated by underscores.

*   **Example:** `phoenix_lxc_configs.json`

## 3. LXC Containers

LXC container names should be descriptive and include the container ID.

*   **Example:** `lxc-955-ollama-oWUI`

## 4. Virtual Machines

Virtual machine names should be descriptive and include the VM ID.

*   **Example:** `vm-100-dev-desktop`