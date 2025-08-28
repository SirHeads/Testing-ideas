# `phoenix_establish_hypervisor.sh` - Execution Flow & Design Summary

## Overview

This document outlines the planned execution flow and key design decisions for the `phoenix_establish_hypervisor.sh` orchestrator script. This script is the main entry point for automating the creation and configuration of LXC containers based on JSON configuration files.

## Execution Flow

1.  **Initialization & Environment Setup:**
    *   Source common library functions from `/usr/local/phoenix_hypervisor/lib/*.sh`.
    *   Define hardcoded paths to main configuration files:
        *   Hypervisor Config: `/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json`
        *   LXC Config: `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`
        *   LXC Config Schema: `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json`
    *   Initialize main log file.

2.  **Configuration Loading & Validation:**
    *   Load `phoenix_hypervisor_config.json`.
    *   Validate `phoenix_hypervisor_config.json` against its schema (if defined).
    *   Load `phoenix_lxc_configs.json`.
    *   Validate `phoenix_lxc_configs.json` against `phoenix_lxc_configs.schema.json` using `ajv` or similar.
    *   Extract global NVIDIA settings (`nvidia_driver_version`, `nvidia_repo_url`) from the LXC config JSON.

3.  **Proxmox Host Initial Setup:**
    *   Execute `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_initial_setup.sh`.

4.  **Iterate Through LXC Configurations:**
    *   Loop through the `lxc_configs` object from the validated `phoenix_lxc_configs.json`. Process containers in numerical order of their CTID keys.
    *   For each `CTID` and its `config_block`:
        *   **Log Start:** Log the processing of this container (e.g., "Processing CTID 901").
        *   **Call LXC Creation Script:**
            *   Execute: `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_create_lxc.sh CTID`
            *   The sub-script will re-parse `phoenix_lxc_configs.json` to get its specific `config_block`.
            *   Handle exit status. On failure, log, consider simple rollback (e.g., destroy container), and decide to continue or exit based on failure handling strategy.
        *   **Wait for LXC Readiness:**
            *   Use a robust mechanism (e.g., polling with `pct exec CTID -- uptime` or `pct status CTID`) to ensure the container is fully booted and responsive.
        *   **Conditional NVIDIA Setup:**
            *   Check `config_block.gpu_assignment`.
            *   If NOT `"none"`:
                *   Execute: `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_nvidia.sh CTID`
                *   The sub-script handles re-parsing for its config and performing idempotency checks.
                *   Handle exit status with potential simple rollback.
        *   **Conditional Docker Setup:**
            *   Check `config_block.features` for `nesting=1`.
            *   If present:
                *   Execute: `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_docker.sh CTID`
                *   The sub-script handles re-parsing for its config and performing idempotency checks.
                *   Handle exit status with potential simple rollback.
        *   **Conditional Specific Setup:**
            *   Check if `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_setup_${CTID}.sh` exists and is executable.
            *   If it exists:
                *   Execute: `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_setup_${CTID}.sh CTID`
                *   The sub-script handles re-parsing for its config if needed.
                *   Handle exit status (likely just log failure, don't destroy container).
        *   **Log Completion:** Log successful completion for this container.

5.  **Finalization:**
    *   Log a summary of actions.
    *   Exit with an appropriate code.

## Key Design Decisions & Clarifications

1.  **Configuration Source:** The orchestrator uses hardcoded paths to load its configuration JSON files. The legacy bash config file (`phoenix_hypervisor_config.txt`) is not sourced by the orchestrator.
2.  **Simplicity Focus:** The approach prioritizes simplicity and ease of understanding/development over maximum performance or complex features, suitable for an internal Dev/Ops tool.
3.  **JSON Parsing by Sub-scripts:** Sub-scripts (e.g., `phoenix_hypervisor_create_lxc.sh`) will re-parse the main `phoenix_lxc_configs.json` file using `jq` to extract their specific configuration block. This avoids complex argument passing of JSON strings.
4.  **Execution Context:** Sub-scripts are executed as separate processes using their full path (e.g., `/usr/local/phoenix_hypervisor/bin/script.sh`).
5.  **LXC Readiness:** Initial implementation will use `pct exec` (e.g., polling `pct exec CTID -- uptime`) to wait for containers to become responsive.
6.  **Rollback Scope:** Rollback on failure for a specific container will be limited (e.g., log error, potentially destroy the specific container that failed). It will not attempt to undo successful steps on other containers.
7.  **Processing Order:** Containers are processed one at a time, in numerical order of their CTID, to simplify the initial implementation.
8.  **Idempotency:** Scripts will implement idempotency checks. Before performing an action, they will check if it's already been done (e.g., container exists, software is installed). If so, they will skip the action. This allows the orchestrator to be re-run to add new containers or fix partial setups.
9.  **Error Handling & Logging:** Consistent error checking (exit codes) and logging (start/stop of key functions) will be used throughout, leveraging common functions from the library.
10. **File System Layout:**
    *   `/usr/local/phoenix_hypervisor/bin/`: Contains executable scripts (`phoenix_establish_hypervisor.sh`, `phoenix_hypervisor_*.sh`).
    *   `/usr/local/phoenix_hypervisor/etc/`: Contains configuration files (`.json`, `.schema.json`), token files, and Docker-related files.
    *   `/usr/local/phoenix_hypervisor/lib/`: Contains common function libraries (`.sh`) sourced by other scripts.