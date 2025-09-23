---
title: 'Feature: Base Setup'
summary: The `base_setup` feature is the foundational customization script for all new LXC containers, ensuring a consistent set of essential packages and a correctly configured OS environment.
document_type: "Feature Summary"
status: "Approved"
version: "1.0.0"
author: "Phoenix Hypervisor Team"
owner: "Developer"
tags:
  - "Base Setup"
  - "OS Configuration"
  - "Package Installation"
  - "LXC Template"
  - "Container Initialization"
review_cadence: "Annual"
last_reviewed: "2025-09-23"
---
The `base_setup` feature is the foundational customization script for all new LXC containers. It ensures that every container starts with a consistent set of essential packages and a correctly configured operating system environment.

## Key Actions

1.  **Package Installation:** Installs a suite of essential command-line tools, including `curl`, `wget`, `vim`, `htop`, `jq`, `git`, and `rsync`.
2.  **System Updates:** Performs an `apt-get update` and `apt-get upgrade` to ensure the container's software is up-to-date.
3.  **Locale Configuration:** Sets the system locale to `en_US.UTF-8` to ensure consistent text encoding and processing.
4.  **Idempotency:** The script is fully idempotent. It creates a marker file (`/.phoenix_base_setup_complete`) upon successful completion and will not re-run on subsequent executions.

## Usage

This feature is typically the first item in the `features` array in the `phoenix_lxc_configs.json` file for any new container being created from a base OS template.
