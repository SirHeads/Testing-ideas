# Phoenix Setup Monitoring Plan

This plan outlines the steps to monitor the execution of the `phoenix setup` command in real-time.

## 1. Real-Time Log Monitoring

The `phoenix-cli` script and its sub-scripts log their output to `/usr/local/phoenix_hypervisor/logs/phoenix_hypervisor.log`. It is highly recommended to monitor this log file in real-time during the setup process.

**Instructions:**

1.  Open a new terminal session on the Proxmox host.
2.  Use the `tail` command to follow the log file:

    ```bash
    tail -f /usr/local/phoenix_hypervisor/logs/phoenix_hypervisor.log
    ```

3.  Keep this terminal window visible throughout the setup process. It will provide a detailed, real-time view of the script's execution, including any warnings or errors.

## 2. Key Events to Watch For

-   **Package Installation**: Look for any errors during `apt-get` operations.
-   **ZFS Pool Creation**: Pay close attention to the output of the `zpool create` commands. Any errors here could indicate a problem with the specified disks.
-   **NVIDIA Driver Installation**: This is a critical and often lengthy step. Monitor for any compilation errors or messages indicating that the driver failed to install.
-   **System Reboot**: The script will trigger a reboot after the NVIDIA driver installation. Be prepared for the system to go down and come back up.
-   **Service Restarts**: Watch for any failures when services like `networking`, `nfs-kernel-server`, or `smbd` are restarted.

## 3. Post-Execution Validation

After the `phoenix setup` command completes and the system has rebooted, use the post-execution validation steps in the `phoenix_setup_preflight_checklist.md` to verify that the setup was successful.