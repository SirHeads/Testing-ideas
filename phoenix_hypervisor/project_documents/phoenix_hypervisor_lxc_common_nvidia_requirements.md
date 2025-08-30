# `phoenix_hypervisor_lxc_common_nvidia.sh` - Requirements

## Overview

This document outlines the detailed requirements for the `phoenix_hypervisor_lxc_common_nvidia.sh` script. This script configures NVIDIA GPU support inside a specific LXC container by passing through host devices and installing the necessary driver and CUDA toolkit.

## Key Aspects & Responsibilities

*   **Role:** Configure NVIDIA GPU support inside an LXC container.
*   **Input:**
    *   `CTID` (Container ID) as a mandatory command-line argument.
    *   Environment variables set by the orchestrator: `GPU_ASSIGNMENT`, `NVIDIA_DRIVER_VERSION`, `NVIDIA_REPO_URL`, `NVIDIA_RUNFILE_URL`.
*   **Process:**
    *   Modifies the LXC config file on the Proxmox host to pass through GPU devices.
    *   Uses `pct exec` to run commands inside the container to install the NVIDIA driver (via `.run` file) and CUDA toolkit.
    *   Restarts the container to apply changes.
*   **Execution Context:** Runs non-interactively on the Proxmox host. Uses `pct` and file system commands.
*   **Idempotency:** Checks if NVIDIA components are already installed/configured inside the container and skips actions if they are.
*   **Error Handling:** Provides detailed logs for all actions and failures. Exits with a standard code: 0 for success, non-zero for failure.
*   **Output:** Detailed logs indicating the steps taken and the outcome of the configuration process.

## Function Sequence, Content, and Purpose

### `main()`
*   **Content:**
    *   Entry point.
    *   Calls `parse_arguments` to get the CTID.
    *   Calls `validate_inputs` (CTID, required environment variables).
    *   Calls `check_container_exists` (basic sanity check).
    *   Calls `configure_host_gpu_passthrough`.
    *   Calls `install_nvidia_software_in_container`.
    *   Calls `restart_container`.
    *   Calls `exit_script`.
*   **Purpose:** Controls the overall flow of the NVIDIA configuration process.

### `parse_arguments()`
*   **Content:**
    *   Checks the number of command-line arguments.
    *   If not exactly one argument is provided, logs a usage error message and calls `exit_script 2`.
    *   Assigns the first argument to a variable `CTID`.
    *   Logs the received CTID.
*   **Purpose:** Retrieves the CTID from the command-line arguments.

### `validate_inputs()`
*   **Content:**
    *   Validates that `CTID` is a positive integer. If not, logs a fatal error and calls `exit_script 2`.
    *   Checks if the required environment variables are set and not empty: `GPU_ASSIGNMENT`, `NVIDIA_DRIVER_VERSION`, `NVIDIA_REPO_URL`, `NVIDIA_RUNFILE_URL`. If any are missing/empty, logs a fatal error and calls `exit_script 2`.
*   **Purpose:** Ensures the script has the necessary and valid inputs (CTID, environment variables) to proceed.

### `check_container_exists()`
*   **Content:**
    *   Logs checking for the existence of container `CTID`.
    *   Executes `pct status "$CTID" > /dev/null 2>&1`.
    *   Captures the exit code.
    *   If the exit code is non-zero (container does not exist or error), logs a fatal error and calls `exit_script 3`.
    *   If the exit code is 0 (container exists), logs confirmation.
*   **Purpose:** Performs a basic sanity check that the target container exists.

### `configure_host_gpu_passthrough()`
*   **Content:**
    *   Logs starting host GPU passthrough configuration for container `CTID`.
    *   Defines the LXC config file path: `LXC_CONF_FILE="/etc/pve/lxc/${CTID}.conf"`.
    *   Checks if `LXC_CONF_FILE` exists. If not, logs a fatal error and calls `exit_script 4`.
    *   Defines the standard set of non-GPU-specific NVIDIA devices/mounts needed:
        *   `/dev/nvidiactl`
        *   `/dev/nvidia-uvm`
        *   `/dev/nvidia-uvm-tools`
        *   `/dev/nvidia-caps` (directory)
    *   Initializes an empty list/array for mount entries to be added.
    *   Based on `GPU_ASSIGNMENT`:
        *   If "none", logs that no GPU assignment is configured, skips adding GPU device mounts. Proceeds to add standard mounts only.
        *   If not "none":
            *   Splits `GPU_ASSIGNMENT` by comma to get a list of indices (e.g., ["0", "1"]).
            *   Iterates through the indices:
                *   For each index `IDX`:
                    *   Constructs the device path: `DEVICE_PATH="/dev/nvidia${IDX}"`.
                    *   Checks if `DEVICE_PATH` exists on the host (`test -e "$DEVICE_PATH"`).
                    *   If it does not exist, logs a warning/error (device not found on host) and potentially continues or exits based on strictness (assume exists per earlier discussion).
                    *   Constructs the `lxc.mount.entry` line for the GPU device: `lxc.mount.entry = ${DEVICE_PATH} ${DEVICE_PATH} none bind,optional,create=file 0 0`.
                    *   Adds this line to the list of mount entries.
    *   Iterates through the standard set of devices/mounts:
        *   For each `STD_DEVICE`:
            *   Checks if it exists on the host.
            *   Constructs the appropriate `lxc.mount.entry` line.
            *   Adds this line to the list of mount entries.
    *   Iterates through the final list of `mount entries`:
        *   For each `ENTRY`:
            *   Checks if the exact line already exists in `LXC_CONF_FILE` (e.g., `grep -Fxq "$ENTRY" "$LXC_CONF_FILE"`).
            *   If it does NOT exist:
                *   Logs appending the entry.
                *   Appends the entry to `LXC_CONF_FILE` (e.g., `echo "$ENTRY" >> "$LXC_CONF_FILE"`).
                *   Handles potential errors (e.g., permission denied).
            *   If it exists, logs that the entry is already present.
    *   Logs completion of host GPU passthrough configuration.
*   **Purpose:** Modifies the LXC container's configuration file on the host to bind-mount the necessary NVIDIA devices from the host into the container's filesystem.

### `install_nvidia_software_in_container()`
*   **Content:**
    *   Logs starting NVIDIA software installation inside container `CTID`.
    *   Defines paths/constants:
        *   `RUNFILE_DEST_PATH="/tmp/nvidia-driver-installer.run"` (path inside the container).
    *   **Idempotency Check:**
        *   Logs performing idempotency check.
        *   Executes `pct exec "$CTID" -- nvidia-smi --version`.
        *   Captures the exit code and output.
        *   If the exit code is 0:
            *   Parses the output to check if the version matches `NVIDIA_DRIVER_VERSION`.
            *   If it matches, logs that NVIDIA driver/CUDA appears to be correctly installed. Skips remaining installation steps. Returns.
        *   If the exit code is non-zero or version mismatch, logs that installation is needed.
    *   **Add NVIDIA Repository:**
        *   Logs adding NVIDIA repository inside the container.
        *   Executes `pct exec "$CTID" --` command to add `NVIDIA_REPO_URL` to the container's APT sources (e.g., `echo "deb $NVIDIA_REPO_URL $(lsb_release -cs) main" > /etc/apt/sources.list.d/nvidia.conf` or similar). Handles errors.
        *   Executes `pct exec "$CTID" -- apt-get update`. Handles errors.
    *   **Download NVIDIA Driver `.run` File:**
        *   Logs downloading NVIDIA driver `.run` file from `NVIDIA_RUNFILE_URL` to `RUNFILE_DEST_PATH` inside the container.
        *   Executes `pct exec "$CTID" -- curl -fL -o "$RUNFILE_DEST_PATH" "$NVIDIA_RUNFILE_URL"` (or `wget`). Handles errors (download failure, network issues).
    *   **Install NVIDIA Driver (`.run` file):**
        *   Logs making the `.run` file executable.
        *   Executes `pct exec "$CTID" -- chmod +x "$RUNFILE_DEST_PATH"`. Handles errors.
        *   Logs installing NVIDIA driver using the `.run` file.
        *   Executes `pct exec "$CTID" -- "$RUNFILE_DEST_PATH" --no-kernel-module --silent` (add other flags as needed). Handles errors (installation failure, incompatible kernel headers if not using `--no-kernel-module` correctly).
    *   **Install CUDA and Utilities (via `apt`):**
        *   Logs installing CUDA drivers and utilities via `apt`.
        *   Derives the major version from `NVIDIA_DRIVER_VERSION` (e.g., 580 from 580.76.05).
        *   Executes `pct exec "$CTID" -- apt-get install -y cuda-drivers-${MAJOR_VERSION}` (or `cuda-toolkit-${MAJOR_VERSION}` if full toolkit is needed). Handles errors.
        *   Executes `pct exec "$CTID" -- apt-get install -y nvtop`. Handles errors.
    *   **Verify Installation (inside Container):**
        *   Logs verifying NVIDIA installation inside the container.
        *   Executes `pct exec "$CTID" -- nvidia-smi`.
        *   Captures and logs the output to show driver status and recognized GPUs.
        *   Handles errors (driver not functioning after install).
    *   Logs completion of NVIDIA software installation.
*   **Purpose:** Installs the NVIDIA driver (using the `.run` file) and CUDA toolkit/utilities inside the LXC container using `pct exec`.

### `restart_container()`
*   **Content:**
    *   Logs restarting container `CTID` to apply configuration changes.
    *   Defines timeout and polling interval (e.g., 60 seconds, 3 seconds).
    *   **Stop Container:**
        *   Executes `pct stop "$CTID"`.
        *   Handles errors.
    *   **Wait for Stopped:**
        *   Initializes timer.
        *   Loop:
            *   Executes `pct status "$CTID"`.
            *   Checks if status is 'stopped'.
            *   If 'stopped', breaks loop.
            *   If not 'stopped', sleeps for interval.
            *   Checks if timeout exceeded. If so, logs error and calls `exit_script 6`.
    *   **Start Container:**
        *   Executes `pct start "$CTID"`.
        *   Handles errors.
    *   **Wait for Running:**
        *   Initializes timer.
        *   Loop:
            *   Executes `pct status "$CTID"`.
            *   Checks if status is 'running'.
            *   If 'running', breaks loop.
            *   If not 'running', sleeps for interval.
            *   Checks if timeout exceeded. If so, logs error and calls `exit_script 6`.
    *   Logs successful restart of container `CTID`.
*   **Purpose:** Restarts the LXC container to ensure the new device mounts and installed software are active.

### `exit_script(exit_code)`
*   **Content:**
    *   Accepts an integer `exit_code`.
    *   If `exit_code` is 0:
        *   Logs a success message (e.g., "NVIDIA configuration for container CTID completed successfully").
    *   If `exit_code` is non-zero:
        *   Logs a failure message indicating the script encountered an error.
    *   Ensures logs are flushed.
    *   Exits the script with the provided `exit_code`.
*   **Purpose:** Provides a single point for script termination, ensuring final logging and correct exit status based on the overall outcome.

## Exit Codes
*   **0:** Success
*   **1:** General error
*   **2:** Invalid input/arguments
*   **3:** Container does not exist
*   **4:** Host GPU passthrough configuration error
*   **5:** NVIDIA software installation/configuration error
*   **6:** Container restart failed