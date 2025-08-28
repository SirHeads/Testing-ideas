# `phoenix_hypervisor_setup_<CTID>.sh` - Pattern Summary

## Overview

This document summarizes the purpose, responsibilities, and interaction pattern of the `phoenix_hypervisor_setup_<CTID>.sh` script family within the Phoenix Hypervisor system. These scripts provide a mechanism for performing container-specific, final-stage customization after the generic LXC creation, NVIDIA setup, and Docker setup steps have been completed by the orchestrator and its dedicated scripts.

## Purpose

The `phoenix_hypervisor_setup_<CTID>.sh` scripts are optional, custom scripts designed to tailor a specific LXC container for its unique role or requirements. While the main orchestrator and its core scripts (`phoenix_hypervisor_create_lxc.sh`, `phoenix_hypervisor_lxc_nvidia.sh`, `phoenix_hypervisor_lxc_docker.sh`) handle generic setup, these specific scripts allow for fine-grained control. Examples include pulling specific AI models, configuring specialized software environments, setting up unique services, or performing application-specific initialization that doesn't fit into the standard NVIDIA/Docker setup flows.

## Key Responsibilities

1.  **Container-Specific Customization:**
    *   Execute any commands or processes required to finalize the setup of a container for its designated purpose.
    *   This can include file manipulation *inside* the container, running specific installers or scripts *inside* the container, starting unique services *inside* the container, or even making final adjustments to the container's configuration *on the host*.

2.  **Conditional Execution:**
    *   These scripts are *optional*. The orchestrator (`phoenix_establish_hypervisor.sh`) checks for their existence based on the `CTID`.
    *   If the script `phoenix_hypervisor_setup_<CTID>.sh` exists and is executable, the orchestrator will run it.
    *   If it does not exist, the orchestrator simply skips this step for that container.

3.  **Execution Context:**
    *   Run non-interactively on the Proxmox host.
    *   Typically use `pct exec <CTID> -- <command>` to run commands *inside* the target LXC container.
    *   May also interact with the host filesystem or Proxmox API if needed for host-level configurations specific to that container.

4.  **Input & Integration:**
    *   Receive the `CTID` as a command-line argument from the orchestrator.
    *   May rely on environment variables set by the orchestrator (e.g., paths, flags).
    *   May parse parts of `phoenix_lxc_configs.json` if they need access to the container's specific configuration details not passed directly by the orchestrator.

5.  **Error Handling & Logging:**
    *   Should provide detailed logs of their actions.
    *   Should handle errors gracefully. A failure in a specific setup script should ideally log the error and potentially exit with a non-zero code, but the orchestrator's behavior on such a failure (whether it continues with other containers) would be defined by the orchestrator's error handling logic (likely just log and move on).

## Naming Convention & Discovery

*   **Naming:** Scripts must follow the exact naming pattern: `phoenix_hypervisor_setup_<CTID>.sh`, where `<CTID>` is the numerical Container ID of the container they are meant to configure (e.g., `phoenix_hypervisor_setup_901.sh` for container 901).
*   **Location:** Scripts are expected to be located in a designated directory, likely the same directory as the main orchestrator script or a dedicated `bin` directory (e.g., `/usr/local/phoenix_hypervisor/bin/`).
*   **Discovery:** The orchestrator (`phoenix_establish_hypervisor.sh`) dynamically constructs the potential script name based on the `CTID` it's currently processing and checks for the file's existence and executability.

## Interaction with Other Components

*   **Called By:** `phoenix_establish_hypervisor.sh` as the final step in processing a specific container, *after* the generic creation, NVIDIA, and Docker setup scripts have run (if applicable).
*   **Input:** `CTID` (integer) as a command-line argument. Potentially environment variables from the orchestrator.
*   **Configuration Source:** May read `phoenix_lxc_configs.json` to get specific details about the container it's setting up.
*   **Reports To:** `phoenix_establish_hypervisor.sh` via exit code and logs.
*   **Precedes:** No further automated steps within the Phoenix Hypervisor framework for that specific container. The container is considered fully set up after this script (if it exists) completes.

## Output & Error Handling

*   **Output:** Detailed logs indicating the specific customization steps taken and their outcomes.
*   **Error Handling:** Standard exit codes (0 for success, non-zero for failure) to communicate status to the orchestrator. Detailed logging is crucial for diagnosing issues with custom setups.