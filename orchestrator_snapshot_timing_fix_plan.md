# Orchestrator Snapshot Timing Fix Plan

## I. Problem Analysis

The root cause of the NVIDIA installation failure for template containers like CTID 901 is a logical flaw in the orchestrator's state machine. The current order of operations is:

1.  `ensure_container_defined`: Clones the container (e.g., 901) from a base template (e.g., 900).
2.  `apply_configurations`: Applies basic settings like memory and networking.
3.  `create_pre_configured_snapshot`: Takes a snapshot of this partially configured container.
4.  `apply_features`: Attempts to apply the `nvidia` feature, which adds passthrough settings to the `.conf` file.

This workflow is incorrect. When the container is restarted in the `apply_features` step, Proxmox prioritizes the configuration stored in the parent snapshot, which lacks the NVIDIA passthrough settings. The newly added settings are ignored, the device nodes are never created in the container, and the script fails.

## II. Solution

The order of operations in the `main_state_machine` function within `phoenix_orchestrator.sh` must be changed. The features, which modify the container's fundamental hardware access, must be applied *before* any snapshots are taken.

The corrected workflow will be:

1.  `ensure_container_defined`
2.  `apply_configurations`
3.  `apply_features` **(Moved up)**
4.  `start_container`
5.  `run_application_script`
6.  `run_health_check`
7.  `create_pre_configured_snapshot` **(Moved down)**

This ensures that when the `pre-configured` snapshot is taken, it captures the container in its fully configured state, including all necessary hardware passthrough settings.

## III. Implementation Steps

The `states` array within the `main_state_machine` function in `usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh` will be reordered to reflect the corrected workflow.