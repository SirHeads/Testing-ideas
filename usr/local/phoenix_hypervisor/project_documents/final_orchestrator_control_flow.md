---
title: Final Orchestrator Control Flow
summary: This document outlines the corrected control flow for the Phoenix Orchestrator, resolving a race condition related to Proxmox's idmap generation for unprivileged containers.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Orchestration
- Control Flow
- Idempotency
- LXC
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Final Orchestrator Control Flow

## 1. Corrected Control Flow Explanation

The primary issue in the previous control flow was a race condition related to Proxmox's `idmap` generation for unprivileged containers. The `idmap`, which is crucial for mapping user and group IDs for shared volumes, is only created by Proxmox when a container is started for the very first time.

The original script attempted to apply shared volumes (`apply_shared_volumes`) immediately after defining and configuring the container, but *before* the container had ever been started. This resulted in failures because the `idmap` file did not yet exist, making it impossible to correctly set permissions for the shared storage.

The new, corrected control flow resolves this timing issue by introducing an explicit finalization step. After the container is defined and its basic resources (memory, cores, disk) are configured, the new `finalize_container_config` function is called. This function performs a simple but critical action: it starts and then immediately stops the container. This cycle forces Proxmox to complete its initial setup process and generate the necessary `idmap` file on the host.

With the `idmap` now guaranteed to be present, the script can safely proceed to the `apply_shared_volumes` step, ensuring all subsequent operations that depend on the `idmap` will execute reliably.

The definitive workflow is now as follows:
1.  `ensure_container_defined`: Creates or clones the container.
2.  `ensure_container_configured`: Sets memory, cores, disk size, etc.
3.  **`finalize_container_config`**: Starts and stops the container to force `idmap` generation.
4.  `apply_shared_volumes`: Applies shared storage mounts, now with a guaranteed `idmap`.
5.  `start_container`: Starts the container for regular operation.
6.  `apply_features`: Installs software and applies configurations inside the container.
7.  `run_application_script`: Executes the final application-specific scripts.

## 2. New `finalize_container_config` Function

This function encapsulates the logic for starting and stopping the container to finalize its configuration.

```bash
# ==============================================================================
# FUNCTION: finalize_container_config
# DESCRIPTION: Finalizes the container configuration by starting and stopping it,
#              which forces Proxmox to generate the necessary idmap before
#              shared volumes are applied.
# PARAMETERS:
#   $1 - CTID (Container ID)
# USAGE: finalize_container_config <ctid>
# EXIT CODES:
#   0 - Success
#   1 - Failure
# ==============================================================================
finalize_container_config() {
    local ctid="$1"
    
    if [ -z "$ctid" ]; then
        log_error "CTID cannot be empty in finalize_container_config."
        return 1
    fi

    log_info "Finalizing configuration for CT $ctid to generate idmap..."

    log_info "Starting container $ctid to trigger idmap creation..."
    if ! pct start "$ctid"; then
        log_error "Failed to start container $ctid during finalization."
        return 1
    fi

    log_info "Stopping container $ctid..."
    if ! pct stop "$ctid"; then
        log_error "Failed to stop container $ctid during finalization."
        return 1
    fi

    log_info "Configuration for CT $ctid finalized successfully. idmap is now available."
    return 0
}
```

## 3. Main Script Logic Snippet

The following snippet demonstrates how the `finalize_container_config` function is integrated into the main orchestration logic of `phoenix_orchestrator.sh`.

```bash
# ... (script initialization and variable loading) ...

main() {
    # ... (loop through containers) ...

    # 1. Define and configure the container
    ensure_container_defined "$ctid" "$hostname" "$template"
    ensure_container_configured "$ctid" "$memory" "$cores" "$disk_size"

    # 2. Finalize configuration to ensure idmap is generated
    finalize_container_config "$ctid"

    # 3. Apply shared volumes now that idmap is guaranteed to exist
    apply_shared_volumes "$ctid"

    # 4. Start the container for application setup
    start_container "$ctid"

    # 5. Apply features and run application scripts
    apply_features "$ctid"
    run_application_script "$ctid"

    log_info "Successfully completed orchestration for CT $ctid."
    
    # ... (end of loop) ...
}

main "$@"