# GPU Passthrough Diagnostic Report

## 1. Summary of the Problem

The NVIDIA driver installation is failing within LXC container 901 during the automated creation process orchestrated by `phoenix_orchestrator.sh`. The failure occurs in the `phoenix_hypervisor_feature_install_nvidia.sh` script, which times out while waiting for the NVIDIA GPU devices to become available inside the container after a restart. This prevents the driver installation from proceeding, leading to a critical failure in the container setup.

## 2. Analysis of the Log File

The log file clearly shows the sequence of events leading to the failure:

*   **Container Creation and Configuration:** The orchestrator successfully clones container 901 from a template and applies the initial configurations.
*   **Feature Installation:** The orchestrator begins applying features, starting with `base_setup`, which completes successfully.
*   **NVIDIA Feature Execution:** The `phoenix_hypervisor_feature_install_nvidia.sh` script is executed.
    *   The script correctly identifies that the NVIDIA feature is not yet installed.
    *   It proceeds to add the necessary GPU passthrough settings to the container's configuration file (`/etc/pve/lxc/901.conf`).
    *   It restarts the container to apply these new settings.
*   **Critical Failure Point:** After the restart, the script's pre-flight check fails. The log shows the following fatal error:
    ```
    2025-09-22 20:23:04 [FATAL] phoenix_hypervisor_feature_install_nvidia.sh: Timeout reached. NVIDIA device not found in CTID 901 after 30 seconds.
    ```
This timeout indicates that despite the configuration changes, the NVIDIA devices (`/dev/nvidia*`) are not appearing inside the container's filesystem as expected.

## 3. Analysis of Scripts and Configuration Files

### `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`

*   The configuration for CTID `901` explicitly assigns GPUs `0` and `1` via `"gpu_assignment": "0,1"`.
*   It also includes `"nvidia"` in its list of features, which correctly triggers the execution of the NVIDIA installation script.

### `usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh`

*   The orchestrator's state machine executes `apply_configurations` before `apply_features`.
*   Within the `apply_configurations` function (lines 545-566), there is a logic block that *also* adds GPU passthrough entries to the container's configuration file if the `nvidia` feature is detected.
*   This means the GPU passthrough settings are being written to the configuration file *twice*: once by the orchestrator and once by the NVIDIA feature script.

### `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_nvidia.sh`

*   The script's `configure_host_gpu_passthrough` function (lines 73-133) is responsible for adding the passthrough settings and restarting the container.
*   The script checks if the configuration entries already exist. Due to the redundant step in the orchestrator, these entries are already present.
*   Crucially, the script includes the logic `if [ "$changes_made" = true ]; then ... restart ... fi`. Because the orchestrator has already added the lines, the feature script finds no changes to make (`changes_made` remains `false`), and therefore **skips the container restart**.
*   The script then immediately proceeds to the `install_drivers_in_container` function, which fails because the container was never restarted to actually apply the passthrough settings that the orchestrator had written.

## 4. Primary Hypothesis for Root Cause

The root cause of the failure is a **race condition and a logical flaw** in the orchestration process. The `phoenix_orchestrator.sh` script prematurely adds the GPU passthrough configuration, which prevents the `phoenix_hypervisor_feature_install_nvidia.sh` script from detecting that a change has been made. As a result, the feature script incorrectly skips the essential container restart required to make the GPU devices available, leading to the timeout.

The sequence of events is as follows:

1.  **Orchestrator (`apply_configurations`)**: Adds GPU passthrough settings to `901.conf`.
2.  **Orchestrator (`apply_features`)**: Calls the NVIDIA feature script.
3.  **NVIDIA Script**: Checks `901.conf`, sees the settings are already there, and determines no changes are needed.
4.  **NVIDIA Script**: Skips the container restart because it believes no changes were made.
5.  **NVIDIA Script**: Tries to find `/dev/nvidia0` inside the container, but it doesn't exist because the container was never restarted with the new configuration.
6.  **NVIDIA Script**: Times out and fails.

## 5. Recommended Next Steps for Remediation

To resolve this issue, the redundant logic in the `phoenix_orchestrator.sh` script must be removed. The responsibility for configuring GPU passthrough and restarting the container should belong exclusively to the `phoenix_hypervisor_feature_install_nvidia.sh` script.

**Specific Recommendation:**

*   **Remove the GPU passthrough configuration block** from the `apply_configurations` function in [`usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh`](usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh:545) (lines 545-566).

This change will ensure that the NVIDIA feature script is solely responsible for managing the GPU configuration, allowing it to correctly detect the necessary changes and perform the required container restart.