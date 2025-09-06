---
title: "phoenix_hypervisor_config.json - Summary"
tags: ["Configuration", "Hypervisor", "Phoenix Hypervisor", "System Settings", "File Paths", "Network Defaults", "Proxmox Defaults", "Script Behavior"]
summary: "This document summarizes the purpose, structure, and role of the `phoenix_hypervisor_config.json` file, which serves as the central configuration point for system-wide settings and default values within the Phoenix Hypervisor system."
version: "1.0.0"
author: "Phoenix Hypervisor Team"
---

This document summarizes the purpose, structure, and role of the `phoenix_hypervisor_config.json` file within the Phoenix Hypervisor system. This file serves as the central configuration point for system-wide settings and default values used by the orchestrator and its associated scripts.

## Overview

This document summarizes the purpose, structure, and role of the `phoenix_hypervisor_config.json` file within the Phoenix Hypervisor system. This file serves as the central configuration point for system-wide settings and default values used by the orchestrator and its associated scripts.

## Purpose

The `phoenix_hypervisor_config.json` file defines essential file paths, network defaults, Proxmox resource defaults, and behavioral flags for the Phoenix Hypervisor scripts. It acts as a single source of truth for the environment in which the LXC containers are created and managed. Unlike the `phoenix_lxc_configs.json` which defines *what* containers to create, this file defines the *environment* in which they are created and how the toolset itself behaves.

## Key Responsibilities

*   **Define Core File Paths:**
    *   Specifies the locations of other critical configuration files (`phoenix_lxc_configs.json`, its schema).
    *   Specifies the locations of token files (Hugging Face, Docker Hub) required for specific setups.
    *   Specifies the location of shared resources (Docker images/contexts).
    *   Defines directories for internal use (marker files, libraries).
*   **Set Network Defaults:**
    *   Defines the external Docker registry URL (e.g., Docker Hub username/namespace).
    *   Specifies the IP address and ports for the Portainer Server and Agent communication, ensuring containers can connect correctly.
*   **Establish Proxmox Defaults:**
    *   Provides default values for LXC container creation parameters (CPU cores, memory, network settings, features, security) that can be overridden by individual container configurations in `phoenix_lxc_configs.json`.
    *   Specifies the default ZFS storage pool for LXC disks.
*   **Control Script Behavior:**
    *   Contains flags that influence the runtime behavior of the orchestrator and scripts (e.g., `rollback_on_failure`, `debug_mode`).

## Structure & Content

The file is a JSON object containing several top-level keys:

*   `$schema`: URI pointing to the JSON schema for validation (if applicable, though a specific schema for this file wasn't created in our discussion).
*   `version`: A string indicating the configuration file version.
*   `author`: A string identifying the author(s).
*   `core_paths`: An object containing paths to essential files and directories.
    *   `lxc_config_file`: Path to `phoenix_lxc_configs.json`.
    *   `lxc_config_schema_file`: Path to `phoenix_lxc_configs.schema.json`.
    *   `hf_token_file`: Path to the Hugging Face token file.
    *   `docker_token_file`: Path to the Docker Hub token file.
    *   `docker_images_path`: Path to the shared Docker images directory.
    *   `hypervisor_marker_dir`: Directory for marker files.
    *   `hypervisor_marker`: Full path to the main initialization marker file.
*   `network`: An object containing network-related settings.
    *   `external_registry_url`: Base URL for the external Docker registry.
    *   `portainer_server_ip`: IP address of the Portainer Server container.
    *   `portainer_server_port`: Port for the Portainer web UI.
    *   `portainer_agent_port`: Port for Portainer Agent communication.
*   `proxmox_defaults`: An object containing default settings for Proxmox LXC creation.
    *   `zfs_lxc_pool`: Default ZFS pool name.
    *   `lxc`: An object with default LXC parameters.
        *   `cores`: Default number of CPU cores.
        *   `memory_mb`: Default memory in MB.
        *   `network_config`: Default network configuration string for `pct`.
        *   `features`: Default LXC features string.
        *   `security`: Default security profile.
        *   `nesting`: Default nesting value (1 for enabled).
*   `docker`: An object containing Docker-related settings.
    *   `portainer_server_image`: Docker image for Portainer Server.
    *   `portainer_agent_image`: Docker image for Portainer Agent.
*   `behavior`: An object containing runtime behavior flags.
    *   `rollback_on_failure`: Boolean to enable/disable rollback on script failure.
    *   `debug_mode`: Boolean to enable/disable debug logging/skip validations.

## Interaction with Other Components

*   **Consumed By:** `phoenix_establish_hypervisor.sh` (and potentially other top-level scripts) to determine where to find configuration files, what default values to use, and how to behave.
*   **References:** Paths and settings defined here are used by various sub-scripts called by the orchestrator.
*   **Input Source:** This file is loaded by the orchestrator based on a hardcoded path or a path derived from this file itself.

## Output & Error Handling

*   **Output:** This file itself produces no output; it is a static configuration input.
*   **Error Handling:** The consuming scripts (especially `phoenix_establish_hypervisor.sh`) are responsible for validating the existence and correctness of the paths and values defined within this file. If a path is invalid or a required value is missing, the consuming script should log an error and exit.