# LXC NVIDIA Passthrough Timing Fix Plan

## I. Problem Analysis

The current NVIDIA installation script for LXC containers is failing due to a race condition. The `configure_host_gpu_passthrough` function correctly modifies the container's configuration and restarts it. However, the script then immediately proceeds to the in-container installation steps. The host's kernel requires a few seconds after the container starts to create and map the `/dev/nvidia*` device nodes. The script's `wait_for_nvidia_device` function, which runs inside the container, times out because it executes before these device nodes exist.

## II. Solution

The `wait_for_nvidia_device` check must be performed as part of the host-level configuration, immediately after the container is restarted. This will pause the script's execution until the GPU passthrough is fully initialized and visible within the container, resolving the race condition.

## III. Implementation Steps

The following changes will be made to `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_nvidia.sh`:

1.  **Move the `wait_for_nvidia_device` function:** This function will be kept.
2.  **Modify `configure_host_gpu_passthrough`:**
    -   After the `run_pct_command start "$CTID"` command, a call to `wait_for_nvidia_device "$CTID"` will be added.
    -   The existing `wait_for_container_initialization` call will be removed, as the device check is a more reliable indicator that the container is ready for this specific feature.
3.  **Modify `install_drivers_in_container`:**
    -   The initial call to `wait_for_nvidia_device` will be removed from this function, as the check will now be completed in the preceding `configure_host_gpu_passthrough` step.

This change ensures a logical and robust workflow: configure the host, restart the container, **wait for the passthrough to be active**, and only then proceed with the in-container driver installation.