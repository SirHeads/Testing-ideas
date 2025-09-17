---
title: Script Guide - phoenix_hypervisor_common_utils.sh
summary: This document provides a comprehensive guide to the `phoenix_hypervisor_common_utils.sh` script, detailing its purpose, usage, and the functions it provides.
document_type: Guide
status: Final
version: 1.0.0
author: Roo
tags:
  - Phoenix Hypervisor
  - Script Guide
  - Utilities
  - Common Functions
---

# Script Guide: `phoenix_hypervisor_common_utils.sh`

## 1. Introduction

This guide provides detailed documentation for the `phoenix_hypervisor_common_utils.sh` script. This script is a core component of the Phoenix Hypervisor system, providing a centralized library of shell functions and environment settings that are sourced by other scripts to ensure consistency and reliability.

## 2. Purpose

The primary purpose of this script is to establish a standardized execution environment for all scripts within the Phoenix Hypervisor framework. It centralizes logging, error handling, configuration management, and common utility functions to avoid code duplication and simplify maintenance.

## 3. Usage

This script is not designed to be executed directly. Instead, it should be sourced at the beginning of other shell scripts.

### Syntax

```bash
source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh
```

## 4. Script Breakdown

### Environment Setup

The script sets up a consistent environment by:
*   **Setting Shell Options**: `set -e` and `set -o pipefail` are used for robust error handling, ensuring that scripts exit immediately on error.
*   **Exporting Global Constants**: Defines and exports paths for key configuration and log files, such as `HYPERVISOR_CONFIG_FILE` and `MAIN_LOG_FILE`.
*   **Dynamic Configuration Path**: Intelligently sets the `LXC_CONFIG_FILE` path based on whether the script is executing on the Proxmox host or within a container's temporary environment (`/tmp/phoenix_run`).
*   **Configuring Locale**: Sets `LANG` and `LC_ALL` to `en_US.UTF-8` to ensure consistent text processing.
*   **Defining Color Codes**: Sets up color codes for formatted log messages to improve readability.

### Configuration Variables

*   `HYPERVISOR_CONFIG_FILE`: Path to the main hypervisor configuration (`/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json`).
*   `LXC_CONFIG_SCHEMA_FILE`: Path to the JSON schema for validating LXC configurations (`/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json`).
*   `MAIN_LOG_FILE`: Path to the main log file where all script output is aggregated (`/var/log/phoenix_hypervisor.log`).
*   `LXC_CONFIG_FILE`: Path to the LXC configuration file, dynamically set to either the host path or a temporary path inside a container.

### Functions

#### Logging Functions

*   **`log_debug(message)`**: Logs a debug message if the `PHOENIX_DEBUG` environment variable is set to `true`.
*   **`log_info(message)`**: Logs a standard informational message.
*   **`log_success(message)`**: Logs a success message, typically used to indicate the successful completion of a significant operation.
*   **`log_warn(message)`**: Logs a warning message to `stderr`.
*   **`log_error(message)`**: Logs an error message to `stderr`.
*   **`log_fatal(message)`**: Logs a fatal error message to `stderr` and immediately exits the script with a status code of 1.
*   **`log_plain_output()`**: A pipe-friendly function to log multi-line output from commands, preserving formatting.

#### Execution Functions

*   **`pct_exec(ctid, command)`**: Executes a command inside a specified LXC container. It is context-aware and will execute commands directly if run from within the container's temporary environment.
*   **`run_pct_command(pct_args)`**: A robust wrapper for executing `pct` commands. It includes error handling and supports a `DRY_RUN` mode, which logs the command instead of executing it.
*   **`retry_command(command)`**: Attempts to execute a command up to three times, with a 5-second delay between retries, before failing.

#### Configuration Functions

*   **`jq_get_value(ctid, jq_query)`**: A wrapper for `jq` to safely query a single value from the `phoenix_lxc_configs.json` file for a specific container.
*   **`jq_get_array(ctid, jq_query)`**: A wrapper for `jq` to retrieve all elements of a JSON array from the configuration file.

#### System Check Functions

*   **`check_root()`**: Verifies that the script is being run with root privileges and exits if it is not.
*   **`check_package(package_name)`**: Checks if a given Debian package is installed.
*   **`check_network_connectivity(host)`**: Pings a specified host up to three times to verify network connectivity.
*   **`check_internet_connectivity()`**: Pings Google's public DNS server (`8.8.8.8`) to verify internet access.
*   **`check_interface_in_subnet(subnet)`**: Checks if any network interface is configured within a given IPv4 subnet.

#### ZFS Functions

*   **`create_zfs_dataset(pool, dataset, mountpoint, [properties])`**: Creates a new ZFS dataset with a specified mountpoint and optional properties.
*   **`set_zfs_properties(dataset, properties)`**: Sets one or more properties on a specified ZFS dataset.
*   **`zfs_pool_exists(pool)`**: Checks if a ZFS pool with a given name exists.
*   **`zfs_dataset_exists(dataset)`**: Checks if a ZFS dataset with a given name exists.

#### NFS Functions

*   **`configure_nfs_export(dataset, mountpoint, subnet, options)`**: Adds an NFS export entry to `/etc/exports` and refreshes the NFS service.
*   **`verify_nfs_exports()`**: Verifies that the NFS exports can be listed without error.

#### User Management Functions

*   **`add_user_to_group(username, group)`**: Adds a user to a specified group if they are not already a member.

#### NVIDIA Functions

*   **`ensure_nvidia_repo_is_configured(ctid)`**: An idempotent function that ensures the NVIDIA CUDA repository is configured within a container. It checks for an existing configuration and, if not found, adds the repository and updates the package list.

## 5. Dependencies

*   **jq**: For parsing JSON configuration files.
*   **Proxmox VE Tools**: `pct` for container management.
*   **Standard Linux Utilities**: `dpkg-query`, `ping`, `ip`, `zfs`, `zpool`, `usermod`, `exportfs`, `wget`, `curl`, `gpg`, `apt-get`.

## 6. Error Handling

The script incorporates robust error handling. The `set -e` and `set -o pipefail` options ensure that the script will exit immediately if any command fails. The logging functions (`log_error`, `log_fatal`) provide clear error messages, and `log_fatal` will terminate the script execution, preventing further issues.

## 7. Customization

This script is designed to be a central utility library and should generally not be modified. Customizations for specific LXC containers or hypervisor features should be implemented in their respective scripts that source this utility file.