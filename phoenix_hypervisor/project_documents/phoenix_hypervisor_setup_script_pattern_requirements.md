# `phoenix_hypervisor_setup_<CTID>.sh` - Pattern Requirements

## Overview

This document outlines the detailed requirements for scripts following the `phoenix_hypervisor_setup_<CTID>.sh` naming pattern. These scripts provide a mechanism for performing container-specific, final-stage customization after the generic LXC creation, NVIDIA setup, and Docker setup steps have been completed by the main orchestrator and its dedicated scripts.

## 1. Key Aspects & Responsibilities

*   **Role:** Perform optional, highly specific final configuration steps for a single LXC container identified by its Container ID (`CTID`).
*   **Trigger:** Execution is initiated by the main orchestrator script, `phoenix_establish_hypervisor.sh`, if the script file exists and is executable.
*   **Scope:** Actions are tailored exclusively to the needs of the single container the script is named for. This can include tasks inside the container (via `pct exec`) or host-level configurations specific to that container.
*   **Execution Context:** Runs non-interactively on the Proxmox host. Assumes the target LXC container is created and running.
*   **Idempotency:** Scripts should be designed to be idempotent where possible, allowing them to be re-run safely without causing errors or unintended side effects if the desired state is already achieved.
*   **Error Handling:** Should provide detailed logs for actions taken and failures encountered. Should handle errors gracefully and report status back to the orchestrator.
*   **Independence:** Each script is independent and should not rely on the internal workings or state of another specific setup script.

## 2. Function Sequence, Content, and Purpose (Pattern)

### `main()`
*   **Content:**
    *   Entry point.
    *   Calls `parse_arguments` to get the CTID.
    *   Calls `validate_inputs` (CTID).
    *   Calls `check_container_exists` (basic sanity check).
    *   Calls `perform_container_specific_setup`. This is the core function where the unique logic for this container's setup resides.
    *   Calls `exit_script`.
*   **Purpose:** Controls the overall flow of the specific container setup process.

### `parse_arguments()`
*   **Content:**
    *   Check the number of command-line arguments.
    *   If not exactly one argument is provided, log a usage error message and call `exit_script 1`.
    *   Assign the first argument to a variable `CTID`.
    *   Log the received CTID.
*   **Purpose:** Retrieves the CTID from the command-line arguments passed by the orchestrator.

### `validate_inputs()`
*   **Content:**
    *   Validate that `CTID` is a positive integer. If not, log a fatal error and call `exit_script 1`.
    *   (Optional) Validate that `CTID` matches the script's own filename pattern (e.g., if the script is `phoenix_hypervisor_setup_901.sh`, `CTID` should be `901`). This adds robustness.
*   **Purpose:** Ensures the script received a valid CTID.

### `check_container_exists()`
*   **Content:**
    *   Log checking for the existence of container `CTID`.
    *   Execute `pct status "$CTID" > /dev/null 2>&1`.
    *   Capture the exit code.
    *   If the exit code is non-zero (container does not exist or error), log a fatal error and call `exit_script 1`.
    *   If the exit code is 0 (container exists), log confirmation.
*   **Purpose:** Performs a basic sanity check that the target container exists.

### `perform_container_specific_setup()`
*   **Content:**
    *   **This is the variable core of the script.**
    *   The specific actions implemented here define the script's purpose.
    *   Common patterns for actions within this function include:
        *   **Executing commands inside the container:** Using `pct exec <CTID> -- <command>` to run shell commands, install software, start services, or configure applications *inside* the LXC.
        *   **Copying files:** Transferring configuration files or data into the container (e.g., `cat localfile | pct exec <CTID> -- tee /path/in/container > /dev/null`).
        *   **Pulling/Loading Docker Images (if Docker is available in the container):** Using `pct exec <CTID> -- docker pull <image>` or `pct exec <CTID> -- docker load -i <file>`.
        *   **Running specific applications or scripts inside the container:** `pct exec <CTID> -- /path/to/container/script.sh`.
        *   **Making host-level configurations specific to this container:** (Less common, but possible) Modifying files on the Proxmox host that relate specifically to this container instance.
        *   **Waiting for services:** Implementing loops or checks to ensure a service started inside the container is fully ready before proceeding.
    *   This function should log its actions and check the success of critical commands.
    *   It should implement its own idempotency checks where applicable (e.g., check if a file already exists, check if a service is already running).
*   **Purpose:** Executes the unique sequence of steps required to finalize the setup of the specific LXC container this script is associated with.

### `exit_script(exit_code)`
*   **Content:**
    *   Accept an integer `exit_code`.
    *   If `exit_code` is 0:
        *   Log a success message (e.g., "Specific setup for container CTID completed successfully").
    *   If `exit_code` is non-zero:
        *   Log a failure message indicating the script encountered an error during the specific setup.
    *   Ensure logs are flushed.
    *   Exit the script with the provided `exit_code`.
*   **Purpose:** Provides a single point for script termination, ensuring final logging and correct exit status based on the outcome of the specific setup.

## 3. Naming Convention & Discovery

*   **Naming:** Scripts MUST follow the exact naming pattern: `phoenix_hypervisor_setup_<CTID>.sh`, where `<CTID>` is the numerical Container ID of the container they are meant to configure (e.g., `phoenix_hypervisor_setup_901.sh`).
*   **Location:** Scripts are expected to be located in a designated directory, likely `/usr/local/phoenix_hypervisor/bin/`, where the orchestrator can find them.
*   **Discovery:** The orchestrator (`phoenix_establish_hypervisor.sh`) dynamically constructs the potential script name based on the `CTID` it's currently processing and checks for the file's existence and executability at the expected path.

## 4. Input & Environment

*   **Primary Input:** `CTID` (integer) passed as the first and only command-line argument by the orchestrator.
*   **Environment Variables:** The orchestrator may set specific environment variables for the script to use (e.g., paths defined in `phoenix_hypervisor_config.json`). Scripts should be designed to consume these if needed.
*   **Configuration Access:** Scripts may parse `phoenix_lxc_configs.json` to retrieve the specific configuration block for the container they are setting up, if required for their logic.

## 5. Output & Error Handling

*   **Output:** Detailed logs indicating the specific customization steps taken, checks performed, and their outcomes. Logs should be sent to stdout/stderr and potentially a central log file managed by the orchestrator.
*   **Error Handling:**
    *   Standard exit codes:
        *   `0`: Success (specific setup completed or determined it was already complete/idempotent).
        *   Non-zero: Failure (e.g., invalid input, `pct exec` failure, critical command failure during setup).
    *   Detailed logging is crucial for diagnosing issues with custom setups. Log messages should be clear and indicate the step where a failure occurred.