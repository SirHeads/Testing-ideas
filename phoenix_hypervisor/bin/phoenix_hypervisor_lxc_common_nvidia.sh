#!/bin/bash
#
# File: phoenix_hypervisor_lxc_nvidia.sh
# Description: Configures NVIDIA GPU support inside a specific LXC container.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script configures NVIDIA GPU support inside an LXC container by passing
# through host devices and installing the necessary driver and CUDA toolkit.
#
# Usage: CTID=<CTID> GPU_ASSIGNMENT=<assignment> NVIDIA_DRIVER_VERSION=<version> NVIDIA_REPO_URL=<url> NVIDIA_RUNFILE_URL=<url> ./phoenix_hypervisor_lxc_nvidia.sh <CTID>
# Requirements:
#   - Proxmox host environment
#   - pct command
#   - jq (if needed for complex parsing, though not required here)
#   - curl or wget (inside the container, assumed to be present or installed by this script if needed)
#
# Exit Codes:
#   0: Success
#   1: General error
#   2: Invalid input/arguments
#   3: Container does not exist
#   4: Host configuration error
#   5: Software installation error
#   6: Container restart error

# =====================================================================================
# main()
#   Content:
#     - Entry point.
#     - Calls parse_arguments to get the CTID.
#     - Calls validate_inputs (CTID, required environment variables).
#     - Calls check_container_exists (basic sanity check).
#     - Calls configure_host_gpu_passthrough.
#     - Calls install_nvidia_software_in_container.
#     - Calls restart_container.
#     - Calls exit_script.
#   Purpose: Controls the overall flow of the NVIDIA configuration process.
# =====================================================================================

# --- Main Script Execution Starts Here ---

# =====================================================================================
# parse_arguments()
#   Content:
#     - Check the number of command-line arguments.
#     - If not exactly one argument is provided, log a usage error message and call exit_script 1.
#     - Assign the first argument to a variable CTID.
#     - Log the received CTID.
#   Purpose: Retrieves the CTID from the command-line arguments.
# =====================================================================================

# =====================================================================================
# validate_inputs()
#   Content:
#     - Validate that CTID is a positive integer. If not, log a fatal error and call exit_script 1.
#     - Check if the required environment variables are set and not empty: GPU_ASSIGNMENT, NVIDIA_DRIVER_VERSION, NVIDIA_REPO_URL, NVIDIA_RUNFILE_URL. If any are missing/empty, log a fatal error and call exit_script 1.
#     - Log the values of the validated environment variables.
#     - (Optional) Validate the format of GPU_ASSIGNMENT against the pattern ^(|[0-9]+(,[0-9]+)*)$.
#   Purpose: Ensures the script has the necessary and valid inputs (CTID, environment variables) to proceed.
# =====================================================================================

# =====================================================================================
# check_container_exists()
#   Content:
#     - Log checking for the existence of container CTID.
#     - Execute pct status "$CTID" > /dev/null 2>&1.
#     - Capture the exit code.
#     - If the exit code is non-zero (container does not exist or error), log a fatal error and call exit_script 1.
#     - If the exit code is 0 (container exists), log confirmation.
#   Purpose: Performs a basic sanity check that the target container exists.
# =====================================================================================

# =====================================================================================
# configure_host_gpu_passthrough()
#   Content:
#     - Log starting host GPU passthrough configuration for container CTID.
#     - Define the LXC config file path: LXC_CONF_FILE="/etc/pve/lxc/${CTID}.conf".
#     - Check if LXC_CONF_FILE exists. If not, log a fatal error and call exit_script 1.
#     - Define the standard set of non-GPU-specific NVIDIA devices/mounts needed:
#         - /dev/nvidiactl
#         - /dev/nvidia-uvm
#         - /dev/nvidia-uvm-tools
#         - /dev/nvidia-caps/ (directory)
#     - Initialize an empty list/array for mount entries to be added.
#     - Based on GPU_ASSIGNMENT:
#         - If "none", log that no GPU assignment is configured, skip adding GPU device mounts. Proceed to add standard mounts only.
#         - If not "none":
#             - Split GPU_ASSIGNMENT by comma to get a list of indices (e.g., ["0", "1"]).
#             - Iterate through the indices:
#                 - For each index IDX:
#                     - Construct the device path: DEVICE_PATH="/dev/nvidia${IDX}".
#                     - Check if DEVICE_PATH exists on the host (test -e "$DEVICE_PATH").
#                     - If it does not exist, log a warning/error (device not found on host) and potentially continue or exit based on strictness (assume exists per earlier discussion).
#                     - Construct the lxc.mount.entry line for the GPU device: lxc.mount.entry = ${DEVICE_PATH} ${DEVICE_PATH} none bind,optional,create=file 0 0.
#                     - Add this line to the list of mount entries.
#     - Iterate through the standard set of devices/mounts:
#         - For each STD_DEVICE:
#             - Check if it exists on the host (especially /dev/nvidia-caps/).
#             - Construct the appropriate lxc.mount.entry line (file or directory type).
#             - Add this line to the list of mount entries.
#     - Iterate through the final list of mount entries:
#         - For each ENTRY:
#             - Check if the exact line already exists in LXC_CONF_FILE (e.g., grep -Fxq "$ENTRY" "$LXC_CONF_FILE").
#             - If it does NOT exist:
#                 - Log appending the entry.
#                 - Append the entry to LXC_CONF_FILE (e.g., echo "$ENTRY" >> "$LXC_CONF_FILE").
#                 - Handle potential errors (e.g., permission denied).
#             - If it exists, log that the entry is already present.
#     - Log completion of host GPU passthrough configuration.
#   Purpose: Modifies the LXC container's configuration file on the host to bind-mount the necessary NVIDIA devices from the host into the container's filesystem.
# =====================================================================================

# =====================================================================================
# install_nvidia_software_in_container()
#   Content:
#     - Log starting NVIDIA software installation inside container CTID.
#     - Define paths/constants:
#         - RUNFILE_DEST_PATH="/tmp/nvidia-driver-installer.run" (path inside the container).
#     - Idempotency Check:
#         - Log performing idempotency check.
#         - Execute pct exec "$CTID" -- nvidia-smi --version.
#         - Capture the exit code and output.
#         - If the exit code is 0:
#             - Parse the output to check if the version matches NVIDIA_DRIVER_VERSION.
#             - If it matches, log that NVIDIA driver/CUDA appears to be correctly installed. Skip remaining installation steps. Return.
#         - If the exit code is non-zero or version mismatch, log that installation is needed.
#     - Add NVIDIA Repository:
#         - Log adding NVIDIA repository inside the container.
#         - Execute pct exec "$CTID" -- command to add NVIDIA_REPO_URL to the container's APT sources (e.g., echo "deb $NVIDIA_REPO_URL $(lsb_release -cs) main" > /etc/apt/sources.list.d/nvidia.conf or similar). Handle errors.
#         - Execute pct exec "$CTID" -- apt-get update. Handle errors.
#     - Download NVIDIA Driver .run File:
#         - Log downloading NVIDIA driver .run file from NVIDIA_RUNFILE_URL to RUNFILE_DEST_PATH inside the container.
#         - Execute pct exec "$CTID" -- curl -fL -o "$RUNFILE_DEST_PATH" "$NVIDIA_RUNFILE_URL" (or wget). Handle errors (download failure, network issues).
#     - Install NVIDIA Driver (.run file):
#         - Log making the .run file executable.
#         - Execute pct exec "$CTID" -- chmod +x "$RUNFILE_DEST_PATH". Handle errors.
#         - Log installing NVIDIA driver using the .run file.
#         - Execute pct exec "$CTID" -- "$RUNFILE_DEST_PATH" --no-kernel-module --silent (add other flags as needed). Handle errors (installation failure, incompatible kernel headers if not using --no-kernel-module correctly).
#     - Install CUDA and Utilities (via apt):
#         - Log installing CUDA drivers and utilities via apt.
#         - Derive the major version from NVIDIA_DRIVER_VERSION (e.g., 580 from 580.76.05).
#         - Execute pct exec "$CTID" -- apt-get install -y cuda-drivers-${MAJOR_VERSION} (or cuda-toolkit-${MAJOR_VERSION} if full toolkit is needed). Handle errors.
#         - Execute pct exec "$CTID" -- apt-get install -y nvtop. Handle errors.
#     - Verify Installation (inside Container):
#         - Log verifying NVIDIA installation inside the container.
#         - Execute pct exec "$CTID" -- nvidia-smi.
#         - Capture and log the output to show driver status and recognized GPUs.
#         - Handle errors (driver not functioning after install).
#     - Log completion of NVIDIA software installation.
#   Purpose: Installs the NVIDIA driver (using the .run file) and CUDA toolkit/utilities inside the LXC container using pct exec.
# =====================================================================================

# =====================================================================================
# restart_container()
#   Content:
#     - Log restarting container CTID to apply configuration changes.
#     - Define timeout and polling interval (e.g., 60 seconds, 3 seconds).
#     - Stop Container:
#         - Execute pct stop "$CTID".
#         - Handle errors.
#     - Wait for Stopped:
#         - Initialize timer.
#         - Loop:
#             - Execute pct status "$CTID".
#             - Check if status is 'stopped'.
#             - If 'stopped', break loop.
#             - If not 'stopped', sleep for interval.
#             - Check if timeout exceeded. If so, log error and call exit_script 1.
#     - Start Container:
#         - Execute pct start "$CTID".
#         - Handle errors.
#     - Wait for Running:
#         - Initialize timer.
#         - Loop:
#             - Execute pct status "$CTID".
#             - Check if status is 'running'.
#             - If 'running', break loop.
#             - If not 'running', sleep for interval.
#             - Check if timeout exceeded. If so, log error and call exit_script 1.
#     - Log successful restart of container CTID.
#   Purpose: Restarts the LXC container to ensure the new device mounts and installed software are active.
# =====================================================================================

# =====================================================================================
# exit_script(exit_code)
#   Content:
#     - Accept an integer exit_code.
#     - If exit_code is 0:
#         - Log a success message (e.g., "NVIDIA configuration for container CTID completed successfully").
#     - If exit_code is non-zero:
#         - Log a failure message indicating the script encountered an error.
#     - Ensure logs are flushed.
#     - Exit the script with the provided exit_code.
#   Purpose: Provides a single point for script termination, ensuring final logging and correct exit status based on the overall outcome.
# =====================================================================================
