# `phoenix_hypervisor_initial_setup.sh` - Requirements

## Overview

This document outlines the detailed requirements for the `phoenix_hypervisor_initial_setup.sh` script. This script ensures the Proxmox host environment is prepared for the Phoenix Hypervisor system.

## Key Aspects & Responsibilities

*   **Role:** Perform essential one-time setup and validation on the Proxmox host.
*   **Input:** Relies on `phoenix_hypervisor_config.json` (path hardcoded to `/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json`) for determining paths and settings. Does not directly process `phoenix_lxc_configs.json`.
*   **Process:** Checks for and installs necessary tools, verifies core configuration files and directories, and manages a simple marker file.
*   **Execution Context:** Runs non-interactively directly on the Proxmox host. Assumes it can use `sudo` for package installations if needed.
*   **Idempotency:** Safe to run multiple times. Uses a marker file to potentially skip actions on subsequent runs.
*   **Error Handling:** Prioritizes clear, detailed logging (stdout/stderr) to inform the user of actions and failures. Exits with a non-zero code on critical failure.
*   **Output:** Detailed logs indicating actions taken and status. Creates a marker file upon successful completion.

## Function Sequence, Content, and Purpose

### `main()`
*   **Content:**
    *   Entry point.
    *   Calls `initialize_environment`.
    *   Calls `check_and_create_marker`.
    *   If marker check indicates setup is needed or forced:
        *   Calls `verify_core_config_files`.
        *   Calls `install_required_packages`.
        *   Calls `verify_required_tools`.
        *   Calls `ensure_core_directories_exist`.
        *   Calls `finalize_setup`.
    *   Calls `exit_script`.
*   **Purpose:** Controls the overall flow of the initial setup process.

### `initialize_environment()`
*   **Content:**
    *   Define hardcoded path to `phoenix_hypervisor_config.json`: `HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"`.
    *   Check if `HYPERVISOR_CONFIG_FILE` exists. If not, log a fatal error and call `exit_script 2`.
    *   The script hardcodes the `MARKER_FILE` path and does not parse it from `HYPERVISOR_CONFIG_FILE`.
    *   Define log file path (e.g., `/var/log/phoenix_hypervisor_initial_setup.log`).
    *   Initialize/Clear the log file.
    *   Log script start message with timestamp.
    *   The script defines logging functions internally and does not source common library functions.
*   **Purpose:** Prepares the script's runtime environment, including loading base config and setting up logging.

### `check_and_create_marker()`
*   **Content:**
    *   Define marker file path: `MARKER_FILE="/usr/local/phoenix_hypervisor/lib/.phoenix_hypervisor_initialized"`. (Use path from parsed config if sourced).
    *   Log checking for marker file.
    *   Check if `MARKER_FILE` exists.
    *   If `MARKER_FILE` exists:
        *   Log that marker file found, indicating setup might have been completed previously.
        *   Set internal flag/state indicating setup is likely complete.
    *   If `MARKER_FILE` does not exist:
        *   Log that marker file not found. Setup will proceed.
        *   Set internal flag/state indicating setup is needed.
    *   The script does not implement a `--force` flag.
*   **Purpose:** Determines if the initial setup has been previously completed using a marker file, influencing subsequent actions.

### `verify_core_config_files()`
*   **Content:**
    *   Define a list of core configuration files based on standard paths or those from `HYPERVISOR_CONFIG_FILE`:
        *   `/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json` (this file)
        *   `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`
        *   `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json`
    *   Iterate through the list.
    *   For each file:
        *   Log checking file.
        *   Check if file exists (`test -f`).
        *   If it does not exist, log a fatal error and call `exit_script 1`.
        *   (Optional) Perform a basic readability check (e.g., `jq empty < "$file"`). If it fails, log an error.
*   **Purpose:** Ensures that the essential configuration files required by the Phoenix system are present on the host.

### `install_required_packages()`
*   **Content:**
    *   Define a list of packages to check/install: `PACKAGES=("jq" "curl" "nodejs" "npm")`.
    *   Log starting package installation check.
    *   Update package list: `apt-get update` (handle errors).
    *   Iterate through `PACKAGES`.
    *   For each package:
        *   Log checking for package.
        *   Check if package is installed (e.g., `dpkg -l "$package" > /dev/null 2>&1`).
        *   If not installed:
            *   Log installing package.
            *   Install package: `apt-get install -y "$package"` (handle errors).
            *   If installation fails, log a fatal error and call `exit_script 3`.
        *   If installed, log package already present.
    *   After installing `npm`, install `ajv-cli`:
        *   Log checking for `ajv-cli`.
        *   Check if `ajv` command is available.
        *   If not:
            *   Log installing `ajv-cli` via `npm`.
            *   Run `npm install -g ajv-cli` (handle errors). Use `sudo` if necessary and appropriate.
            *   If installation fails, log a fatal error and call `exit_script 3`.
        *   If installed, log `ajv-cli` already present.
*   **Purpose:** Ensures all necessary command-line tools for the Phoenix scripts are installed on the host.

### `verify_required_tools()`
*   **Content:**
    *   Define a list of critical tools to verify: `TOOLS=("jq" "curl" "pct" "ajv")`.
    *   Log starting tool verification.
    *   Iterate through `TOOLS`.
    *   For each tool:
        *   Log verifying tool.
        *   Check if tool is available in PATH (`command -v "$tool" > /dev/null 2>&1`).
        *   If not available, log a fatal error (tool missing despite install attempt or not found in PATH) and call `exit_script 4`.
*   **Purpose:** Confirms that critical tools are not only installed but also accessible and executable by the script.

### `ensure_core_directories_exist()`
*   **Content:**
    *   Define a list of core directories based on standard paths:
        *   `/usr/local/phoenix_hypervisor/bin`
        *   `/usr/local/phoenix_hypervisor/etc`
        *   `/usr/local/phoenix_hypervisor/lib`
    *   Log ensuring core directories exist.
    *   Iterate through the list.
    *   For each directory:
        *   Log checking/creating directory.
        *   Check if directory exists (`test -d`).
        *   If it does not exist, create it: `mkdir -p "$directory"` (handle errors).
        *   If creation fails, log a fatal error and call `exit_script 1`.
*   **Purpose:** Ensures that the standard directory structure for the Phoenix Hypervisor is present on the host.

### `finalize_setup()`
*   **Content:**
    *   Log finalizing setup.
    *   If setup actions were performed (based on marker check or force):
        *   Log creating marker file.
        *   Create the marker file: `touch "$MARKER_FILE"` (handle errors).
        *   If creation fails, log a warning (setup considered complete but marker failed).
    *   Log that initial host setup is complete.
*   **Purpose:** Performs final actions upon successful completion of setup steps, primarily creating the marker file.

### `exit_script(exit_code)`
*   **Content:**
    *   Accept an integer `exit_code`.
    *   Log the final status message (e.g., "Initial setup completed successfully" for 0, "Initial setup failed" for non-zero).
    *   Ensure logs are flushed.
    *   Exit the script with the provided `exit_code`.
*   **Purpose:** Provides a single point for script termination, ensuring final logging and correct exit status.