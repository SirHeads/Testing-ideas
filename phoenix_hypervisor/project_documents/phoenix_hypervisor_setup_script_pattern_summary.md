# `phoenix_hypervisor_setup_<CTID>.sh` - Pattern Summary

## Overview

This document summarizes the purpose, responsibilities, and interaction pattern of the `phoenix_hypervisor_setup_<CTID>.sh` script family within the Phoenix Hypervisor system. These scripts provide a mechanism for performing container-specific, final-stage customization. Their role varies depending on whether the container is a template or a standard application container, especially within the new snapshot-based creation workflow.

## Purpose

The `phoenix_hypervisor_setup_<CTID>.sh` scripts are optional, custom scripts designed for the final-stage setup of a specific LXC container or template. Their function depends on the type of container they configure:

*   **For Template Containers (`is_template: true`):** The primary purpose is to finalize the environment within the container (e.g., install specific software like vLLM) and then create the ZFS snapshot (`template_snapshot_name`) that other containers will clone from. This script essentially "bakes" the template.
*   **For Standard Application Containers (`is_template: false`):** The purpose is to perform any unique, final configuration steps required for that specific application (e.g., starting a specific model server, pulling a unique dataset). These scripts run *after* the container is created/cloned and ready.

While the main orchestrator and its core/cloning scripts handle generic setup (creation, NVIDIA, Docker) or the cloning process itself, these specific scripts allow for fine-grained control over the final state of both templates and application containers.

## Key Responsibilities

*   **Template Finalization & Snapshot Creation (If `is_template: true`):**
    *   Performs any final software installations or configurations specific to the template's role (e.g., installing vLLM framework).
    *   Verifies that the template environment is correctly set up (e.g., running a test command or checking service status).
    *   **Crucially:** Shuts down the template container and creates the ZFS snapshot specified by `template_snapshot_name` in the container's configuration block. This snapshot becomes the base for cloning dependent containers/templates.
*   **Application Container Customization (If `is_template: false`):**
    *   Executes any commands or processes required to finalize the setup of the application container for its designated purpose.
    *   This can include file manipulation *inside* the container, running specific installers or scripts *inside* the container, starting unique services *inside* the container, or even making final adjustments to the container's configuration *on the host*.
*   **Conditional Execution:**
    *   These scripts are *optional*. The orchestrator (`phoenix_establish_hypervisor.sh`) checks for their existence based on the `CTID`.
    *   If the script `phoenix_hypervisor_setup_<CTID>.sh` exists and is executable, the orchestrator will run it.
    *   If it does not exist, the orchestrator simply skips this step for that container.
*   **Execution Context:**
    *   Runs non-interactively on the Proxmox host.
    *   Typically uses `pct exec <CTID> -- <command>` to run commands *inside* the target LXC container.
    *   May also interact with the host filesystem (e.g., to execute `pct` commands for shutdown/snapshot/start) or Proxmox API if needed for host-level configurations specific to that container.
*   **Input & Integration:**
    *   Receives the `CTID` as a command-line argument from the orchestrator.
    *   May rely on environment variables set by the orchestrator (e.g., paths, flags, specific configuration values like model names).
    *   May parse parts of `phoenix_lxc_configs.json` if they need access to the container's specific configuration details not passed directly by the orchestrator.
*   **Idempotency:**
    *   Should be designed to be idempotent. If run multiple times, they should detect if their specific task (e.g., snapshot creation, service start) is already complete and skip unnecessary actions to prevent errors.
*   **Error Handling & Logging:**
    *   Should provide detailed logs of their actions.
    *   Should handle errors gracefully. A failure should log the error and exit with a non-zero code, signaling the orchestrator. The orchestrator's behavior (stop or continue) will depend on its error handling logic.

## Naming Convention & Discovery

*   **Naming:** Scripts must follow the exact naming pattern: `phoenix_hypervisor_setup_<CTID>.sh`, where `<CTID>` is the numerical Container ID of the container/template they are meant to configure (e.g., `phoenix_hypervisor_setup_920.sh` for template container 920, `phoenix_hypervisor_setup_950.sh` for application container 950).
*   **Location:** Scripts are expected to be located in a designated directory, specifically `/usr/local/phoenix_hypervisor/bin/`.
*   **Discovery:** The orchestrator (`phoenix_establish_hypervisor.sh`) dynamically constructs the potential script name based on the `CTID` it's currently processing and checks for the file's existence and executability at that standard path.

## Interaction with Other Components

*   **Called By:** `phoenix_establish_hypervisor.sh` as a specific step in processing a container/template, invoked after the container is created/cloned and confirmed ready.
*   **Input:** `CTID` (integer) as a command-line argument. Potentially environment variables or specific configuration values passed by the orchestrator.
*   **Configuration Source:** May read `phoenix_lxc_configs.json` to get specific details about the container/template it's setting up (e.g., model name, tensor parallelism).
*   **Reports To:** `phoenix_establish_hypervisor.sh` via exit code and logs.
*   **Precedes:** No further automated steps within the Phoenix Hypervisor framework for that specific container. The container/template is considered fully set up (and snapshot created, if a template) after this script (if it exists) completes successfully.

## Output & Error Handling

*   **Output:** Detailed logs indicating the specific customization steps taken, checks performed, and their outcomes (e.g., "Snapshot 'vllm-base-snapshot' created for container 920", "Qwen3 model server started in container 950").
*   **Error Handling:** Standard exit codes (0 for success, non-zero for failure) to communicate status to the orchestrator. Detailed logging is crucial for diagnosing issues with custom setups or template finalization.