# `phoenix_establish_hypervisor.sh` - Execution Flow & Design Summary

## Overview

This document outlines the planned execution flow and key design decisions for the `phoenix_establish_hypervisor.sh` orchestrator script. This script is the main entry point for automating the creation and configuration of LXC containers and templates based on JSON configuration files, leveraging ZFS snapshots for optimized creation times.

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
    *   Extract global NVIDIA settings (`nvidia_driver_version`, `nvidia_repo_url`, `nvidia_runfile_url`) from the LXC config JSON.

3.  **Proxmox Host Initial Setup:**
    *   Execute `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_initial_setup.sh`.

4.  **Iterate Through LXC Configurations:**
    *   Loop through the `lxc_configs` object from the validated `phoenix_lxc_configs.json`. Process containers/templates, generally in ascending numerical order of their CTID keys to respect potential dependencies (e.g., templates built from other templates).
    *   For each `CTID` and its `config_block`:
        *   **Log Start:** Log the processing of this container/template (e.g., "Processing CTID 901").
        *   **Determine Action (Create/Clone):**
            *   Check `config_block.is_template`.
            *   **If `is_template` is true:**
                *   Check if `config_block.clone_from_template_ctid` exists.
                *   If it exists, call a new function/script to **clone** the container from the specified source template's snapshot: `clone_lxc_from_template(source_CTID, source_snapshot_name, target_CTID, target_config_block)`.
                *   If it does not exist (base template), call the standard **creation** function/script: `create_lxc_container(CTID, config_block)`.
            *   **If `is_template` is false (or omitted):**
                *   Analyze `config_block` (e.g., `gpu_assignment`, `features`, `vllm_model`) or check `config_block.clone_from_template_ctid` to determine the best existing template snapshot to clone from.
                *   Call `clone_lxc_from_template(...)` with the determined source.
        *   **Wait for LXC Readiness:**
            *   Use a robust mechanism (e.g., polling with `pct exec CTID -- uptime` or `pct status CTID`) to ensure the newly created/cloned container is fully booted and responsive.
        *   **(Conditional Setups - Post Clone/Create):** *If* specific setups (NVIDIA, Docker) are required and not fully handled by the cloning process (which should be the goal), they would be called here. However, the aim is for templates to include these, making these steps often redundant or just idempotent checks.
            *   **Conditional NVIDIA Setup:**
                *   Check `config_block.gpu_assignment`.
                *   If NOT `"none"`:
                    *   Execute: `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_nvidia.sh CTID`
                    *   The sub-script handles re-parsing for its config and performing idempotency checks.
                    *   Handle exit status.
            *   **Conditional Docker Setup:**
                *   Check `config_block.features` for `nesting=1`.
                *   If present:
                    *   Execute: `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_docker.sh CTID`
                    *   The sub-script handles re-parsing for its config and performing idempotency checks.
                    *   Handle exit status.
        *   **Conditional Specific Setup:**
            *   Check if `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_setup_${CTID}.sh` exists and is executable.
            *   If it exists:
                *   Execute: `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_setup_${CTID}.sh CTID`
                *   For templates, this script is responsible for finalizing the environment and creating the ZFS snapshot defined by `config_block.template_snapshot_name`.
                *   For standard containers, this script handles unique, final configuration.
                *   The sub-script handles re-parsing for its config if needed.
                *   Handle exit status.
        *   **Finalize Container/Template State:**
            *   Shutdown the container/template: `pct shutdown CTID`.
            *   Wait for shutdown.
            *   Take a final "configured-state" snapshot: `pct snapshot create CTID configured-state`.
            *   Start the container/template: `pct start CTID`.
        *   **Log Completion:** Log successful completion for this container/template.

5.  **Finalization:**
    *   Log a summary of actions.
    *   Exit with an appropriate code.

## Key Design Decisions & Clarifications

1.  **Configuration Source:** The orchestrator uses hardcoded paths to load its configuration JSON files. The legacy bash config file (`phoenix_hypervisor_config.txt`) is not sourced by the orchestrator.
2.  **Snapshot-Based Templates:** The core enhancement is the ability to create and clone from ZFS snapshots. Containers marked with `is_template: true` serve as the basis for these snapshots.
3.  **Explicit Template Cloning:** Templates and containers can explicitly define their source using `clone_from_template_ctid`, creating a clear and manageable hierarchy (e.g., `902` clones from `900`, `910` clones from `902`).
4.  **Simplicity Focus:** The approach prioritizes simplicity and ease of understanding/development over maximum performance or complex features, suitable for an internal Dev/Ops tool.
5.  **JSON Parsing by Sub-scripts:** Sub-scripts (e.g., `phoenix_hypervisor_create_lxc.sh`) will re-parse the main `phoenix_lxc_configs.json` file using `jq` to extract their specific configuration block. This avoids complex argument passing of JSON strings.
6.  **Execution Context:** Sub-scripts are executed as separate processes using their full path (e.g., `/usr/local/phoenix_hypervisor/bin/script.sh`).
7.  **LXC Readiness:** Initial implementation will use `pct exec` (e.g., polling `pct exec CTID -- uptime`) to wait for containers to become responsive.
8.  **Rollback Scope:** Rollback on failure for a specific container will be limited (e.g., log error, potentially destroy the specific container that failed). It will not attempt to undo successful steps on other containers. Failure of a template container will prevent dependent containers from being processed.
9.  **Processing Order:** Containers are generally processed one at a time, in numerical order of their CTID, to help ensure templates are built before containers that depend on them are attempted.
10. **Idempotency:** Scripts will implement idempotency checks. Before performing an action, they will check if it's already been done (e.g., container exists, software is installed, snapshot exists). If so, they will skip the action. This allows the orchestrator to be re-run to add new containers or fix partial setups.
11. **Final State Snapshot:** Every container and template takes a "configured-state" snapshot after its specific setup script completes and before final startup. This provides a clean, consistent image.
12. **Error Handling & Logging:** Consistent error checking (exit codes) and logging (start/stop of key functions) will be used throughout, leveraging common functions from the library. Critical failures will stop the process.
13. **File System Layout:**
    *   `/usr/local/phoenix_hypervisor/bin/`: Contains executable scripts (`phoenix_establish_hypervisor.sh`, `phoenix_hypervisor_*.sh`).
    *   `/usr/local/phoenix_hypervisor/etc/`: Contains configuration files (`.json`, `.schema.json`), token files, and Docker-related files.
    *   `/usr/local/phoenix_hypervisor/lib/`: Contains common function libraries (`.sh`) sourced by other scripts.