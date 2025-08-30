# `phoenix_hypervisor_clone_lxc.sh` - Summary

## Overview

This document provides a summary of the `phoenix_hypervisor_clone_lxc.sh` script, detailing its purpose, key functionalities, and how it integrates into the Phoenix Hypervisor system for efficient LXC container cloning.

## Purpose

The `phoenix_hypervisor_clone_lxc.sh` script is designed to facilitate the rapid creation of new LXC containers by cloning them from existing ZFS snapshots of source containers. It automates the process of applying a new container's specific configuration, including network settings, based on a provided JSON configuration block. This script is a crucial component in the hierarchical template creation strategy, enabling the quick deployment of pre-configured environments.

## Key Aspects & Responsibilities

*   **Efficient LXC Cloning:** Clones an LXC container from a specified source container's ZFS snapshot, significantly reducing deployment time compared to creating from scratch.
*   **Configuration Application:** Applies comprehensive configuration settings to the newly cloned container, including:
    *   Name, memory, CPU cores, storage details.
    *   LXC features and unprivileged status.
    *   Specific network settings (IP, gateway, MAC address, bridge, interface name) using `pct set`.
*   **Input Validation:** Ensures the integrity of the cloning process by validating all input arguments, including CTIDs, snapshot names, and the JSON configuration block.
*   **Source Verification:** Verifies the existence of the source container and its specified ZFS snapshot before initiating the clone operation.
*   **Logging and Error Handling:** Provides detailed logging for all operations and handles various error conditions gracefully, exiting with appropriate status codes to inform the orchestrator.

## Interaction with Other Components

*   **Called By:** The main orchestrator script, `phoenix_establish_hypervisor.sh`, invokes this script to perform the actual cloning of both template containers (derived from other templates) and standard application containers.
*   **Input:** Receives the source CTID, source snapshot name, target CTID, and a JSON configuration block (or key fields from it) as arguments from the orchestrator.
*   **Configuration Source:** Utilizes the provided JSON configuration block to apply specific settings to the new container.
*   **Reports To:** The orchestrator script via exit codes and log messages, indicating the success or failure of the cloning operation.

## Dependencies

*   `pct` (Proxmox VE Container Toolkit): Essential for all LXC container management operations, including cloning and configuration.
*   `jq`: Used for parsing and extracting data from JSON configuration blocks.
*   Proxmox Host Access: Requires appropriate permissions and access to the Proxmox VE host and its defined storage paths (especially ZFS pools for snapshots).