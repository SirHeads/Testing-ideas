# `phoenix_hypervisor_setup_<CTID>.sh` - Pattern Requirements

## Overview

This document outlines the detailed requirements for scripts following the `phoenix_hypervisor_setup_<CTID>.sh` naming pattern. These scripts provide a mechanism for performing container-specific, final-stage customization. Their role and requirements differ based on whether the target container is a template or a standard application container within the Phoenix Hypervisor's snapshot-based workflow.

## Key Aspects & Responsibilities

*   **Role:** Perform optional, highly specific final configuration steps for a single LXC container or template identified by its Container ID (`CTID`).
    *   **For Templates (`is_template: true`):** Finalize the environment (e.g., install vLLM) and create the ZFS snapshot (`template_snapshot_name`) for cloning.
    *   **For Standard Containers (`is_template: false`):** Perform unique final setup (e.g., start a specific model server).
*   **Trigger:** Execution is initiated by the main orchestrator script, `phoenix_establish_hypervisor.sh`, after the container/template is created/cloned and is ready.
*   **Scope:** Actions are tailored exclusively to the needs of the single container/template the script is named for. This can include tasks inside the container (via `pct exec`), host-level `pct` commands (e.g., shutdown/snapshot/start), or host-level configurations specific to that container.
*   **Execution Context:** Runs non-interactively on the Proxmox host.
*   **Idempotency:** Scripts MUST be designed to be idempotent, allowing them to be re-run safely. They should detect if their specific task (e.g., snapshot creation, service start) is already complete and skip actions to prevent errors.
*   **Error Handling:** Should provide detailed logs for actions taken and failures encountered. Should handle errors gracefully and report status back to the orchestrator via exit codes.
*   **Independence:** Each script is independent and should not rely on the internal workings or state of another specific setup script.

## Function Sequence, Content, and Purpose (Pattern)

### `main()`
*   **Content:**
    *   Entry point.
    *   Calls `parse_arguments` to get the CTID.
    *   Calls `validate_inputs` (CTID).
    *   Calls `check_container_exists` (basic sanity check).
    *   Calls `perform_container_specific_setup`. This is the core function where the unique logic for this container's/template's final setup resides.
    *   Calls `exit_script`.
*   **Purpose:** Controls the overall flow of the specific container/template setup process.

### `parse_arguments()`
*   **Content:**
    *   Checks the number of command-line arguments.
    *   If not exactly one argument is provided, logs a usage error message and calls `exit_script 1`.
    *   Assigns the first argument to a variable `CTID`.
    *   Logs the received CTID.
*   **Purpose:** Retrieves the CTID from the command-line arguments passed by the orchestrator.

### `validate_inputs()`
*   **Content:**
    *   Validates that `CTID` is a positive integer. If not, logs a fatal error and calls `exit_script 1`.
    *   (Optional/Recommended) Validates that `CTID` matches the script's own filename pattern (e.g., if the script is `phoenix_hypervisor_setup_920.sh`, `CTID` should be `920`). This adds robustness.
*   **Purpose:** Ensures the script received a valid CTID.

### `check_container_exists()`
*   **Content:**
    *   Logs checking for the existence of container `CTID`.
    *   Executes `pct status "$CTID" > /dev/null 2>&1`.
    *   Captures the exit code.
    *   If the exit code is non-zero (container does not exist or error), logs a fatal error and calls `exit_script 1`.
    *   If the exit code is 0 (container exists), logs confirmation.
*   **Purpose:** Performs a basic sanity check that the target container/template exists.

### `perform_container_specific_setup()`
*   **Content:**
    *   **This is the variable core of the script, and its primary function depends on the container type:**
    *   **If Target is a Template (`is_template: true` in config):**
        *   Executes commands inside the container to finalize the template environment (e.g., `pct exec <CTID> -- apt install vllm`, configure services).
        *   Verifies the environment is correctly set up (e.g., `pct exec <CTID> -- vllm --version`, check service status).
        *   **Crucially:** Shuts down the container: `pct shutdown "$CTID"`.
        *   Waits for shutdown.
        *   Creates the ZFS snapshot: `pct snapshot create "$CTID" "<template_snapshot_name_from_config>"`.
        *   Logs snapshot creation success.
        *   Starts the container: `pct start "$CTID"`.
        *   Waits for start.
    *   **If Target is a Standard Container (`is_template: false` in config):**
        *   Executes commands inside the container for final application setup (e.g., `pct exec <CTID> -- docker run ...`, start services, configure applications).
        *   Copies files into the container if needed.
        *   Pulls/Loads Docker Images if needed.
        *   Runs specific applications or scripts inside the container.
        *   Makes host-level configurations specific to this container if needed.
        *   Waits for services/applications to be ready if needed.
    *   This function should log its actions and check the success of critical commands.
    *   It MUST implement idempotency checks for its core actions (e.g., check if a service is running, check if a snapshot exists before creating it).
*   **Purpose:** Executes the unique sequence of steps required to finalize the setup of the specific LXC container or template this script is associated with, including the critical snapshot creation step for templates.

### `exit_script(exit_code)`
*   **Content:**
    *   Accepts an integer `exit_code`.
    *   If `exit_code` is 0:
        *   Logs a success message (e.g., "Setup for container/template CTID completed successfully. Snapshot 'name' created." for templates, "Setup for container CTID completed." for standard containers).
    *   If `exit_code` is non-zero:
        *   Logs a failure message indicating the script encountered an error during the specific setup (e.g., "Setup for container/template CTID failed during <step>.").
    *   Ensures logs are flushed.
    *   Exits the script with the provided `exit_code`.
*   **Purpose:** Provides a single point for script termination, ensuring final logging and correct exit status based on the outcome of the specific setup.

## Naming Convention & Discovery

*   **Naming:** Scripts MUST follow the exact naming pattern: `phoenix_hypervisor_setup_<CTID>.sh`, where `<CTID>` is the numerical Container ID of the container/template they are meant to configure (e.g., `phoenix_hypervisor_setup_920.sh` for template 920, `phoenix_hypervisor_setup_950.sh` for container 950).
*   **Location:** Scripts are expected to be located in the designated directory: `/usr/local/phoenix_hypervisor/bin/`.
*   **Discovery:** The orchestrator (`phoenix_establish_hypervisor.sh`) dynamically constructs the potential script name based on the `CTID` it's currently processing and checks for the file's existence and executability at the standard path `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_setup_<CTID>.sh`.

## Input & Environment

*   **Primary Input:** `CTID` (integer) passed as the first and only command-line argument by the orchestrator.
*   **Environment Variables:** The orchestrator may set specific environment variables for the script to use (e.g., paths, specific configuration values like model names or ports). Scripts should be designed to consume these if needed.
*   **Configuration Access:** Scripts may parse `phoenix_lxc_configs.json` to retrieve the specific configuration block for the container/template they are setting up, especially to access fields like `template_snapshot_name`, `vllm_model`, or `vllm_tensor_parallel_size`.

## Output & Error Handling

*   **Output:** Detailed logs indicating the specific customization steps taken, checks performed, and their outcomes (e.g., "Creating snapshot 'vllm-base-snapshot' for template 920...", "Model server started in container 950."). Logs should be sent to stdout/stderr and potentially a central log file managed by the orchestrator.
*   **Error Handling:**
    *   Standard exit codes:
        *   `0`: Success (specific setup completed or determined it was already complete/idempotent, snapshot created for templates).
        *   Non-zero: Failure (e.g., invalid input, `pct` command failure, critical command failure during setup, snapshot creation failure for templates).
    *   Detailed logging is crucial for diagnosing issues. Log messages should be clear and indicate the step where a failure occurred.