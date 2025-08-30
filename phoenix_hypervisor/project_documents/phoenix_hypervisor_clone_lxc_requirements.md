# `phoenix_hypervisor_clone_lxc.sh` - Requirements

## Overview

This document outlines the detailed requirements for the `phoenix_hypervisor_clone_lxc.sh` script, which is responsible for cloning LXC containers from existing ZFS snapshots.

## Purpose

The `phoenix_hypervisor_clone_lxc.sh` script's primary purpose is to efficiently create new LXC containers by cloning them from a specified source container's ZFS snapshot. It applies the new container's configuration, including network settings, based on a provided JSON configuration block.

## Key Aspects & Responsibilities

### Functional Requirements

*   **Clone LXC Container:** The script must be able to clone an LXC container from a specified source container's ZFS snapshot.
*   **Configuration from JSON:** The new container's configuration (name, memory, cores, storage, features, unprivileged status) must be derived from a provided JSON configuration block.
*   **Network Configuration:** The script must apply specific network settings (IP, gateway, MAC address, bridge, interface name) to the newly cloned container using `pct set`.
*   **Argument Validation:** The script must validate all input arguments for correctness and existence (e.g., positive integers for CTIDs, non-empty strings, valid JSON).
*   **Source Container and Snapshot Validation:** The script must verify that the source container and the specified snapshot exist before proceeding with the clone operation.
*   **Logging:** The script must log informational and error messages to a central log file (`/var/log/phoenix_hypervisor.log`).
*   **Error Handling:** The script must handle various error conditions gracefully and exit with appropriate error codes.

### Non-Functional Requirements

*   **Performance:** The cloning and configuration process should be efficient.
*   **Reliability:** The script should reliably clone and configure LXC containers without data corruption or unexpected behavior.
*   **Security:** The script should adhere to best practices for shell scripting security.
*   **Maintainability:** The script should be well-structured, commented, and easy to understand and modify.

## Dependencies

*   `pct` (Proxmox VE Container Toolkit)
*   `jq` (for parsing JSON)
*   Access to Proxmox host and defined storage paths.