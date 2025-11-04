# `phoenix create` Diagnostics Plan

This plan outlines the steps to diagnose and verify the `phoenix create` workflow for a single LXC container.

## Objective

To ensure that the `phoenix create` command correctly creates, configures, and starts a new LXC container based on its definition in `phoenix_lxc_configs.json`.

## Test Case: Create a `vllm` Container

This plan will use the creation of a `vllm` container (e.g., CT 910) as the primary test case, as it involves cloning, feature application, and GPU passthrough.

### 1. Pre-creation State Verification

*   **Ensure the target container does not already exist:**
    ```bash
    pct status 910
    ```
    *   **Expected:** Command should fail or indicate the container does not exist. If it exists, it should be deleted (`phoenix delete 910`) before proceeding.
*   **Verify that the clone template (CT 901) exists:**
    ```bash
    pct status 901
    ```
    *   **Expected:** The container should exist. If not, it needs to be created first (`phoenix create 901`).

### 2. Execute the Create Command

*   **Run the `phoenix create` command with the `--dry-run` flag first:**
    ```bash
    phoenix create 910 --dry-run
    ```
    *   **Expected:** The output should show the sequence of commands that *would* be run without actually executing them. This is a safe way to verify the logic.
*   **Run the actual `create` command:**
    ```bash
    phoenix create 910
    ```

### 3. Post-creation Verification

These commands should be run after the `create` command has finished.

*   **Check the status of the new container:**
    ```bash
    pct status 910
    ```
    *   **Expected:** `status: running`
*   **Inspect the container's configuration:**
    ```bash
    pct config 910
    ```
    *   **Expected:** The output should match the settings defined in `phoenix_lxc_configs.json` for CT 910, including memory, cores, networking, and GPU passthrough (`lxc.cgroup2.devices.allow: c 195:* rwm`).
*   **Verify network connectivity:**
    ```bash
    pct exec 910 -- ping -c 3 10.0.0.1
    ```
    *   **Expected:** The ping should be successful.
*   **Verify GPU passthrough:**
    ```bash
    pct exec 910 -- nvidia-smi
    ```
    *   **Expected:** The `nvidia-smi` command should execute successfully and show the details of the assigned GPU(s).
*   **Check the application script logs:**
    The `vllm` containers run an application script (`phoenix_hypervisor_lxc_vllm.sh`). Check for logs to ensure it ran correctly.
    ```bash
    # The exact log location may vary, but check common places.
    pct exec 910 -- journalctl -n 50
    ```

## Expected Outcomes

*   The `phoenix create` command completes without errors.
*   The new LXC container is created and running.
*   The container's configuration in Proxmox matches the JSON definition.
*   The container has network connectivity and can access its assigned hardware (GPUs).
*   Any application-specific setup scripts have run successfully.

This completes the analysis of the `phoenix create` workflow.