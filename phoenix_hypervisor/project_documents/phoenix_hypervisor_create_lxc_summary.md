# `phoenix_hypervisor_create_lxc.sh` - Summary

## Overview

This document summarizes the purpose, responsibilities, and key interactions of the `phoenix_hypervisor_create_lxc.sh` script within the Phoenix Hypervisor system.

## Purpose

The `phoenix_hypervisor_create_lxc.sh` script is responsible for creating a single LXC container on the Proxmox host. It takes a Container ID (CTID) as input, retrieves the corresponding configuration from `phoenix_lxc_configs.json`, and executes the necessary `pct create` command to instantiate the container with the specified resources and settings.

## Key Aspects & Responsibilities

*   **Idempotent Container Creation:**
    *   Receives a CTID as a command-line argument.
    *   Checks if an LXC container with that CTID already exists on the host (e.g., using `pct status`).
    *   If the container exists, logs that creation is being skipped and exits successfully.
    *   If the container does not exist, proceeds with creation.
*   **Configuration Parsing:**
    *   Re-parses the `phoenix_lxc_configs.json` file to retrieve the specific configuration block (`config_block`) associated with the provided CTID.
*   **`pct create` Command Construction & Execution:**
    *   Dynamically constructs the `pct create` command by mapping fields from the `config_block` to `pct` arguments:
        *   `CTID`: From the script argument.
        *   `--hostname`: From `config_block.name`.
        *   `--memory`: From `config_block.memory_mb`.
        *   `--cores`: From `config_block.cores`.
        *   `--template`: From `config_block.template`.
        *   `--storage`: From `config_block.storage_pool`.
        *   `--rootfs`: Size calculated from `config_block.storage_size_gb` (e.g., `config_block.storage_pool:config_block.storage_size_gb`).
        *   `--net0`: Constructed from the `config_block.network_config` object (e.g., `name=eth0,bridge=vmbr0,ip=10.0.0.99/24,gw=10.0.0.1`).
        *   `--features`: Directly from `config_block.features`.
        *   `--unprivileged`: Mapped from the boolean `config_block.unprivileged` (true -> 1, false -> 0).
        *   `--hwaddress`: From `config_block.mac_address`.
    *   Executes the constructed `pct create` command.
*   **Post-Creation Startup:**
    *   If `pct create` is successful, automatically starts the newly created container using `pct start <CTID>`.
*   **Execution Context:**
    *   Runs non-interactively on the Proxmox host.
    *   Utilizes the `pct` command-line tool extensively.
*   **Logging & Error Handling:**
    *   Provides detailed logs of the process, including checks performed, commands run, and outcomes.
    *   Reports success or failure back to the calling orchestrator (`phoenix_establish_hypervisor.sh`) via specific exit codes (0 for success, 2 for invalid input/config, 3 for container creation failure, 4 for container start failure).

## Interaction with Other Components

*   **Called By:** `phoenix_establish_hypervisor.sh` for each LXC container defined in `phoenix_lxc_configs.json`.
*   **Input:** CTID (integer) as a command-line argument.
*   **Configuration Source:** Reads `phoenix_lxc_configs.json` (and potentially `phoenix_hypervisor_config.json` for paths) to get the specific container configuration.
*   **Reports To:** `phoenix_establish_hypervisor.sh` via exit code and logs.
*   **Precedes:** Subsequent setup scripts like `phoenix_hypervisor_lxc_nvidia.sh`, `phoenix_hypervisor_lxc_docker.sh`, and `phoenix_hypervisor_setup_<CTID>.sh`, which are called by the orchestrator *after* this script completes successfully and the container is verified as running.

## Output & Error Handling

*   **Output:** Detailed logs indicating the steps taken (check existence, parse config, run `pct create`, run `pct start`) and the results.
*   **Error Handling:** Specific exit codes (0 for success, 2 for invalid input/config, 3 for container creation failure, 4 for container start failure) to communicate status to the orchestrator. Detailed logging provides context for any failures.