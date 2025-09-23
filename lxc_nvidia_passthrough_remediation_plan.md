# LXC NVIDIA Passthrough Remediation Plan

## I. Problem Analysis

The root cause of the NVIDIA installation failure in LXC containers is that the host-level GPU passthrough configurations (device mounts and cgroup permissions) are not being applied to the container's `.conf` file.

This is confirmed by comparing the generated `/etc/pve/lxc/901.conf` with the working `/etc/pve/lxc/950.conf`. The `lxc.mount.entry` and `lxc.cgroup2.devices.allow` lines are missing from `901.conf`.

The `configure_host_gpu_passthrough` function within `phoenix_hypervisor_feature_install_nvidia.sh` is responsible for this task, but it appears to be failing or not running correctly for CTID 901. The `phoenix_lxc_configs.json` file correctly specifies `"gpu_assignment": "0,1"` for CTID 901, so the issue is not with the configuration data itself, but with its application.

## II. Remediation Steps

The plan is to ensure the `configure_host_gpu_passthrough` function executes correctly and robustly applies the necessary configurations.

1.  **Ensure Correct Execution Flow:**
    -   The main orchestrator (`phoenix_orchestrator.sh`) calls the `apply_features` function.
    -   The `apply_features` function iterates through the features listed for the CTID in `phoenix_lxc_configs.json`.
    -   For the `nvidia` feature, it executes `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_nvidia.sh`.
    -   The *first* action within this script must be to call `configure_host_gpu_passthrough`.

2.  **Refactor `configure_host_gpu_passthrough` for Robustness:**
    -   The function will be modified to be more resilient and provide clearer logging.
    -   It will explicitly check for the existence of each NVIDIA device on the host before attempting to add a mount entry.
    -   It will ensure that any changes to the `.conf` file are immediately followed by a container restart to apply them *before* proceeding to the in-container installation steps.

## III. Implementation Details

The following changes will be made to `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_nvidia.sh`:

-   The `main` function will be restructured to ensure `configure_host_gpu_passthrough` is called before `install_drivers_in_container`.
-   The `configure_host_gpu_passthrough` function will be updated to ensure it correctly parses the `gpu_assignment` string and handles cases where devices might not be present.

This targeted fix will ensure the container is correctly prepared on the host *before* any attempt is made to install drivers inside it, resolving the root cause of the failure.