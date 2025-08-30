# `phoenix_hypervisor_create_lxc.sh` - Requirements

## Overview

This document outlines the detailed requirements for the `phoenix_hypervisor_create_lxc.sh` script. This script is responsible for creating a single LXC container on the Proxmox host based on a specific configuration block.

## Key Aspects & Responsibilities

*   **Role:** Create a single LXC container using `pct create` based on a configuration provided in `phoenix_lxc_configs.json`.
*   **Input:** Accepts a Container ID (CTID) as a mandatory command-line argument. Receives the path to `phoenix_lxc_configs.json` via an environment variable (e.g., `LXC_CONFIG_FILE`) set by the orchestrator.
*   **Process:** Checks if the container exists. If not, parses the configuration for the given CTID and constructs/executes the `pct create` command. Automatically starts the container afterward.
*   **Execution Context:** Runs non-interactively on the Proxmox host. Utilizes the `pct` command-line tool.
*   **Idempotency:** Checks for container existence and skips creation if the container already exists, exiting successfully.
*   **Error Handling:** Provides detailed logs for all actions and failures. Exits with a standard code: 0 for success (created, started, or already existed), non-zero for failure.
*   **Output:** Detailed logs indicating the steps taken and the outcome of the creation process.

## Function Sequence, Content, and Purpose

### `main()`
*   **Content:**
    *   Entry point.
    *   Calls `parse_arguments` to get the CTID.
    *   Calls `validate_inputs` (CTID, `LXC_CONFIG_FILE` env var).
    *   Calls `check_container_exists`.
    *   If container does NOT exist:
        *   Calls `load_and_parse_config` to get the specific `config_block`.
        *   Calls `construct_pct_create_command`.
        *   Calls `execute_pct_create`.
        *   If `execute_pct_create` is successful:
            *   Calls `start_container`.
    *   Calls `exit_script`.
*   **Purpose:** Controls the overall flow of the container creation process.

### `parse_arguments()`
*   **Content:**
    *   Check the number of command-line arguments.
    *   If not exactly one argument is provided, log a usage error message and call `exit_script 2`.
    *   Assign the first argument to a variable `CTID`.
    *   Log the received CTID.
*   **Purpose:** Retrieves the CTID from the command-line arguments.

### `validate_inputs()`
*   **Content:**
    *   Check if the `LXC_CONFIG_FILE` environment variable is set and not empty. If not, log a fatal error and call `exit_script 2`.
    *   Log the value of `LXC_CONFIG_FILE`.
    *   Check if the file specified by `LXC_CONFIG_FILE` exists and is readable. If not, log a fatal error and call `exit_script 2`.
    *   Validate that `CTID` is a positive integer. If not, log a fatal error and call `exit_script 2`.
*   **Purpose:** Ensures the script has the necessary and valid inputs (CTID, config file path) to proceed.

### `check_container_exists()`
*   **Content:**
    *   Log checking for the existence of container `CTID`.
    *   Execute `pct status "$CTID" > /dev/null 2>&1`.
    *   Capture the exit code.
    *   If the exit code is 0 (container exists):
        *   Log that container `CTID` already exists.
        *   Set an internal flag indicating the container exists.
    *   If the exit code is non-zero (container does not exist or error):
        *   Log that container `CTID` does not exist (or status check failed, treat as non-existent for creation).
        *   Set an internal flag indicating the container does not exist.
*   **Purpose:** Determines if the target LXC container already exists to ensure idempotent behavior.

### `load_and_parse_config()`
*   **Content:**
    *   Log loading configuration for container `CTID` from `LXC_CONFIG_FILE`.
    *   Use `jq` to extract the specific `config_block` for `CTID` from `LXC_CONFIG_FILE` (e.g., `jq -r --arg ctid "$CTID" '.lxc_configs[$ctid]' "$LXC_CONFIG_FILE"`).
    *   Store the extracted JSON string in a variable (e.g., `CONFIG_BLOCK_JSON`).
    *   Check if the extracted `CONFIG_BLOCK_JSON` is not null/empty. If it is, log an error (CTID not found in config) and call `exit_script 2`.
    *   Log successful extraction of the config block (potentially a snippet for verification).
*   **Purpose:** Retrieves the specific configuration block for the given `CTID` from the main JSON configuration file.

### `construct_pct_create_command()`
*   **Content:**
    *   Log starting construction of the `pct create` command for `CTID`.
    *   Initialize an empty array or string for the command.
    *   Start with the base command: `pct create`.
    *   Add `CTID`.
    *   Extract and add arguments from `CONFIG_BLOCK_JSON` using `jq`:
        *   `--hostname`: `jq -r '.name' <<< "$CONFIG_BLOCK_JSON"`
        *   `--memory`: `jq -r '.memory_mb' <<< "$CONFIG_BLOCK_JSON"`
        *   `--cores`: `jq -r '.cores' <<< "$CONFIG_BLOCK_JSON"`
        *   `--template`: `jq -r '.template' <<< "$CONFIG_BLOCK_JSON"`
        *   `--storage`: `jq -r '.storage_pool' <<< "$CONFIG_BLOCK_JSON"`
        *   `--rootfs`: Construct as `<storage_pool>:<size>` using `jq` to get `storage_pool` and `storage_size_gb`.
        *   `--net0`: Construct the string `name=...,bridge=...,ip=...,gw=...` by extracting values from the `network_config` sub-object.
        *   `--features`: `jq -r '.features' <<< "$CONFIG_BLOCK_JSON"`
        *   `--hwaddress`: `jq -r '.mac_address' <<< "$CONFIG_BLOCK_JSON"`
        *   `--unprivileged`: Map `jq -r '.unprivileged' <<< "$CONFIG_BLOCK_JSON"` (boolean `true`/`false`) to `1`/`0`.
    *   Log the fully constructed command string (for debugging).
    *   Store the final command string in a variable (e.g., `PCT_CREATE_CMD`).
*   **Purpose:** Dynamically builds the full `pct create` command string based on the parsed `config_block`.

### `execute_pct_create()`
*   **Content:**
    *   Log executing the `pct create` command for `CTID`.
    *   Execute the command stored in `PCT_CREATE_CMD` (e.g., `"${PCT_CREATE_CMD[@]}"` if it's an array).
    *   Capture the exit code.
    *   If the exit code is 0:
        *   Log successful execution of `pct create`.
    *   If the exit code is non-zero:
        *   Log a fatal error indicating `pct create` failed for `CTID`, including the command that was run and the exit code.
        *   Call `exit_script 3`.
*   **Purpose:** Runs the constructed `pct create` command and handles its success or failure.

### `start_container()`
*   **Content:**
    *   Log starting container `CTID`.
    *   Execute `pct start "$CTID"`.
    *   Capture the exit code.
    *   If the exit code is 0:
        *   Log successful start of container `CTID`.
    *   If the exit code is non-zero:
        *   Log a fatal error indicating `pct start` failed for `CTID`, including the exit code.
        *   Call `exit_script 4`. (As per requirement 4: `pct start` failure is a script failure).
*   **Purpose:** Starts the LXC container that was just created.

### `exit_script(exit_code)`
*   **Content:**
    *   Accept an integer `exit_code`.
    *   If `exit_code` is 0:
        *   Log a success message (e.g., "Script completed successfully." or "Container CTID already existed, skipping creation.").
    *   If `exit_code` is non-zero:
        *   Log a failure message indicating the script encountered an error.
    *   Ensure logs are flushed.
    *   Exit the script with the provided `exit_code`.
*   **Purpose:** Provides a single point for script termination, ensuring final logging and correct exit status based on the overall outcome.