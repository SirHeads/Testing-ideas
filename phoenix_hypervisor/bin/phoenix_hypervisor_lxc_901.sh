#!/bin/bash
#
# File: phoenix_hypervisor_setup_901.sh
# Description: Finalizes the setup for LXC container 901 (BaseTemplateGPU) and creates the GPU ZFS snapshot.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script performs final configuration steps for the BaseTemplateGPU LXC container (CTID 901).
# It installs/configures the NVIDIA driver and CUDA toolkit inside the container for GPUs 0 and 1,
# verifies the setup by displaying nvidia-smi output, and then shuts down the container
# to create the 'gpu-snapshot' ZFS snapshot. This snapshot serves as the foundation for
# other GPU-dependent templates and containers.
#
# Usage: ./phoenix_hypervisor_setup_901.sh <CTID>
#   Example: ./phoenix_hypervisor_setup_901.sh 901
#
# Arguments:
#   $1 (CTID): The Container ID, expected to be 901 for BaseTemplateGPU.
#
# Requirements:
#   - Proxmox host environment with 'pct' command available.
#   - Container 901 must be created/cloned and accessible.
#   - jq (for potential JSON parsing if needed).
#   - phoenix_hypervisor_lxc_common_nvidia.sh must be available and functional.
#   - Global NVIDIA settings (nvidia_driver_version, nvidia_repo_url, nvidia_runfile_url)
#     must be available (likely passed by the orchestrator or accessible via config).
#
# Exit Codes:
#   0: Success (Setup completed, snapshot created or already existed).
#   1: General error.
#   2: Invalid input arguments.
#   3: Container 901 does not exist or is not accessible.
#   4: NVIDIA driver/CUDA installation/configuration failed.
#   5: Snapshot creation failed.
#   6: Container shutdown/start failed.

# =====================================================================================
# main()
#   Content:
#     - Entry point.
#     - Calls parse_arguments to get the CTID.
#     - Calls validate_inputs (CTID).
#     - Calls check_container_exists.
#     - Calls check_if_snapshot_exists. If snapshot exists, log and exit 0 (idempotency).
#     - Calls install_and_configure_nvidia_in_container by calling the common script.
#     - Calls verify_nvidia_setup_inside_container (e.g., run nvidia-smi).
#     - Calls shutdown_container.
#     - Calls create_gpu_snapshot.
#     - Calls start_container.
#     - Calls exit_script.
#   Purpose: Controls the overall flow of the BaseTemplateGPU setup and snapshot creation.
# =====================================================================================

# --- Main Script Execution Starts Here ---

# =====================================================================================
# parse_arguments()
#   Content:
#     - Check the number of command-line arguments. Expect exactly one (CTID=901).
#     - If incorrect number of arguments, log a usage error message and call exit_script 2.
#     - Assign the first argument to a variable CTID.
#     - Log the received CTID.
#   Purpose: Retrieves the CTID from the command-line arguments.
# =====================================================================================

# =====================================================================================
# validate_inputs()
#   Content:
#     - Validate that CTID is '901'. While flexible, this script is specifically for 901.
#         - If CTID is not '901', log a warning but continue (or error if strict).
#     - Validate that CTID is a positive integer. If not, log error and call exit_script 2.
#     - (If globals like NVIDIA settings are expected as env vars, could check here)
#   Purpose: Ensures the script received the expected CTID.
# =====================================================================================

# =====================================================================================
# check_container_exists()
#   Content:
#     - Log checking for the existence and status of container CTID.
#     - Execute `pct status "$CTID" > /dev/null 2>&1`.
#     - Capture the exit code.
#     - If the exit code is non-zero (container does not exist or error), log a fatal error and call exit_script 3.
#     - If the exit code is 0 (container exists), log confirmation.
#   Purpose: Performs a basic sanity check that the target BaseTemplateGPU container exists and is manageable.
# =====================================================================================

# =====================================================================================
# check_if_snapshot_exists()
#   Content:
#     - Log checking for the existence of the 'gpu-snapshot'.
#     - Execute `pct snapshot list "$CTID"` and capture output.
#     - Parse the output (e.g., using `jq` or `grep`) to see if 'gpu-snapshot' is listed.
#     - If 'gpu-snapshot' exists:
#         - Log that the snapshot already exists, implying setup is complete or was previously done.
#         - Call exit_script 0. (Idempotency)
#     - If 'gpu-snapshot' does not exist:
#         - Log that the snapshot needs to be created.
#         - Return/Continue to the next step.
#   Purpose: Implements idempotency by checking if the final state (snapshot) already exists.
# =====================================================================================

# =====================================================================================
# install_and_configure_nvidia_in_container()
#   Content:
#     - Log starting NVIDIA driver/CUDA setup inside container CTID.
#     - Define path to the common NVIDIA script: NVIDIA_SCRIPT="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_common_nvidia.sh"
#     - Check if NVIDIA_SCRIPT exists and is executable. Fatal error if not.
#     - Execute the common NVIDIA script, passing CTID and necessary global NVIDIA settings:
#         - Execute: "$NVIDIA_SCRIPT" "$CTID" "$NVIDIA_DRIVER_VERSION" "$NVIDIA_REPO_URL" "$NVIDIA_RUNFILE_URL"
#         - Capture exit code.
#         - If the exit code is non-zero, log a fatal error indicating NVIDIA setup failed and call exit_script 4.
#     - Log NVIDIA driver/CUDA setup completed successfully inside container CTID.
#   Purpose: Delegates the complex task of installing and configuring NVIDIA software to the common script.
# =====================================================================================

# =====================================================================================
# verify_nvidia_setup_inside_container()
#   Content:
#     - Log verifying NVIDIA setup inside container CTID by running nvidia-smi.
#     - Execute `pct exec "$CTID" -- nvidia-smi` and capture output and exit code.
#     - Print the output of `nvidia-smi` to the terminal/log for user visibility.
#     - If the exit code is non-zero, log a fatal error indicating verification failed and call exit_script 4.
#     - Log nvidia-smi verification successful.
#   Purpose: Runs nvidia-smi inside the container to confirm the driver is loaded and can see the GPUs.
# =====================================================================================

# =====================================================================================
# shutdown_container()
#   Content:
#     - Log initiating shutdown of container CTID.
#     - Execute: `pct shutdown "$CTID"`
#     - Capture exit code. If non-zero, log error and call exit_script 6.
#     - Implement a loop to wait for the container to reach 'stopped' status using `pct status "$CTID"`.
#         - Use a timeout (e.g., 3-5 seconds as mentioned) and sleep interval.
#         - If timeout is exceeded before 'stopped', log error and call exit_script 6.
#     - Log container CTID shutdown successfully.
#   Purpose: Safely shuts down the container before creating the ZFS snapshot.
# =====================================================================================

# =====================================================================================
# create_gpu_snapshot()
#   Content:
#     - Log creating ZFS snapshot 'gpu-snapshot' for container CTID.
#     - Execute: `pct snapshot create "$CTID" "gpu-snapshot"`
#     - Capture exit code.
#     - If the exit code is non-zero, log a fatal error indicating snapshot creation failed and call exit_script 5.
#     - If the exit code is 0, log successful creation of 'gpu-snapshot'.
#   Purpose: Creates the ZFS snapshot for the GPU template hierarchy.
# =====================================================================================

# =====================================================================================
# start_container()
#   Content:
#     - Log starting container CTID after snapshot creation.
#     - Execute: `pct start "$CTID"`
#     - Capture exit code. If non-zero, log error and call exit_script 6.
#     - Implement a loop to wait for the container to reach 'running' status using `pct status "$CTID"`.
#         - Use a timeout and sleep interval.
#         - If timeout is exceeded before 'running', log error and call exit_script 6.
#     - Log container CTID started successfully.
#   Purpose: Restarts the container after the snapshot has been created.
# =====================================================================================

# =====================================================================================
# exit_script(exit_code)
#   Content:
#     - Accept an integer exit_code.
#     - If exit_code is 0:
#         - Log a success message (e.g., "BaseTemplateGPU CTID 901 setup and 'gpu-snapshot' creation completed successfully." or "BaseTemplateGPU CTID 901 'gpu-snapshot' already exists, skipping setup.").
#     - If exit_code is non-zero:
#         - Log a failure message indicating the script encountered an error during setup/snapshot creation, specifying the stage if possible.
#     - Ensure logs are flushed.
#     - Exit the script with the provided exit_code.
#   Purpose: Provides a single point for script termination, ensuring final logging and correct exit status.
# =====================================================================================