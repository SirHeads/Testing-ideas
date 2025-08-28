# `phoenix_hypervisor_initial_setup.sh` - Summary

## Overview

This document summarizes the purpose, responsibilities, and key interactions of the `phoenix_hypervisor_initial_setup.sh` script within the Phoenix Hypervisor system.

## Purpose

The `phoenix_hypervisor_initial_setup.sh` script is responsible for performing the essential one-time setup and validation tasks on the **Proxmox host**. Its goal is to ensure that the host environment possesses all the necessary tools, configurations, and baseline conditions required for the subsequent `phoenix_establish_hypervisor.sh` orchestrator and its associated scripts to function correctly and create/configure LXC containers.

## Key Responsibilities

1.  **Tool Installation & Verification:**
    *   Check for the presence of critical command-line utilities required by other Phoenix scripts.
    *   Install any missing tools. Key tools identified include:
        *   `jq`: For parsing and manipulating JSON configuration files.
        *   `curl`: For downloading files or making web requests.
        *   `pct`: The Proxmox Container Toolkit (assumed present on Proxmox, but a check is beneficial).
        *   `ajv-cli` (or similar): For validating JSON files against their schemas.
    *   Update tools to the latest version if necessary (based on configuration preference, though default is latest).

2.  **Environment Validation:**
    *   Verify the existence and basic readability of the core Phoenix Hypervisor configuration files:
        *   `phoenix_hypervisor_config.json`
        *   `phoenix_lxc_configs.json`
        *   `phoenix_lxc_configs.schema.json`
    *   Potentially ensure that core directory structures defined in the configurations exist (e.g., `/usr/local/phoenix_hypervisor/etc/`, `/usr/local/phoenix_hypervisor/bin/`, `/usr/local/phoenix_hypervisor/lib/`).

3.  **Idempotency:**
    *   Designed to be safe to run multiple times. It should check the current state and only perform actions if the required conditions are not already met.

4.  **Marker System:**
    *   Implement a simple marker file mechanism (e.g., creating `/usr/local/phoenix_hypervisor/lib/.phoenix_hypervisor_initialized`) to indicate successful completion of the initial setup. This can help prevent unnecessary re-runs or provide a quick status check.

5.  **Execution Context:**
    *   Runs non-interactively directly on the Proxmox host.
    *   Has full access to the Phoenix Hypervisor configuration files to guide its actions and checks.

## Interaction with Other Components

*   **Called By:** `phoenix_establish_hypervisor.sh` as one of its first major steps.
*   **Reports To:** `phoenix_establish_hypervisor.sh` via its exit code (0 for success, non-zero for failure) and detailed terminal/logs.
*   **Enables:** All subsequent scripts (`phoenix_hypervisor_create_lxc.sh`, `phoenix_hypervisor_lxc_nvidia.sh`, etc.) by ensuring the host has the required foundational tools and setup.

## Output & Error Handling

*   **Output:** Provides detailed logs to the terminal and potentially a log file, clearly indicating which tools were checked/installed, any configurations verified, and the overall success or failure of the setup process.
*   **Error Handling:** Prioritizes clear, informative logging to help the user understand what went wrong and where, in case of a failure. Simple exit codes are sufficient for the orchestrator to detect failure.