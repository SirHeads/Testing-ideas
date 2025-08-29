#!/bin/bash
#
# File: phoenix_hypervisor_setup_903.sh
# Description: Finalizes the setup for LXC container 903 (BaseTemplateDockerGPU) and creates the Docker+GPU ZFS snapshot.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script performs final configuration steps for the BaseTemplateDockerGPU LXC container (CTID 903).
# It verifies that Docker Engine, the NVIDIA Container Toolkit, and direct GPU access (inherited/cloned from 902)
# are correctly configured and functional inside the container. It then shuts down the container
# to create the 'docker-gpu-snapshot' ZFS snapshot. This snapshot serves as the foundation for
# other templates/containers requiring both Docker-in-LXC and direct GPU access.
#
# Usage: ./phoenix_hypervisor_setup_903.sh <CTID>
#   Example: ./phoenix_hypervisor_setup_903.sh 903
#
# Arguments:
#   $1 (CTID): The Container ID, expected to be 903 for BaseTemplateDockerGPU.
#
# Requirements:
#   - Proxmox host environment with 'pct' command available.
#   - Container 903 must be created/cloned and accessible.
#   - jq (for potential JSON parsing if needed).
#   - Container 903 is expected to be cloned from 902's 'docker-snapshot'.
#
# Exit Codes:
#   0: Success (Setup completed, snapshot created or already existed).
#   1: General error.
#   2: Invalid input arguments.
#   3: Container 903 does not exist or is not accessible.
#   4: Verification of Docker/GPU setup inside container failed.
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
#     - Calls verify_docker_and_gpu_setup_inside_container (includes nvidia-smi, docker info, docker run nvidia-smi).
#     - Calls shutdown_container.
#     - Calls create_docker_gpu_snapshot.
#     - Calls start_container.
#     - Calls exit_script.
#   Purpose: Controls the overall flow of the BaseTemplateDockerGPU setup and snapshot creation.
# =====================================================================================

# --- Main Script Execution Starts Here ---

# =====================================================================================
# parse_arguments()
#   Content:
#     - Check the number of command-line arguments. Expect exactly one (CTID=903).
#     - If incorrect number of arguments, log a usage error message and call exit_script 2.
#     - Assign the first argument to a variable CTID.
#     - Log the received CTID.
#   Purpose: Retrieves the CTID from the command-line arguments.
# =====================================================================================

# =====================================================================================
# validate_inputs()
#   Content:
#     - Validate that CTID is '903'. While flexible, this script is specifically for 903.
#         - If CTID is not '903', log a warning but continue (or error if strict).
#     - Validate that CTID is a positive integer. If not, log error and call exit_script 2.
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
#   Purpose: Performs a basic sanity check that the target BaseTemplateDockerGPU container exists and is manageable.
# =====================================================================================

# =====================================================================================
# check_if_snapshot_exists()
#   Content:
#     - Log checking for the existence of the 'docker-gpu-snapshot'.
#     - Execute `pct snapshot list "$CTID"` and capture output.
#     - Parse the output (e.g., using `jq` or `grep`) to see if 'docker-gpu-snapshot' is listed.
#     - If 'docker-gpu-snapshot' exists:
#         - Log that the snapshot already exists, implying setup is complete or was previously done.
#         - Call exit_script 0. (Idempotency)
#     - If 'docker-gpu-snapshot' does not exist:
#         - Log that the snapshot needs to be created.
#         - Return/Continue to the next step.
#   Purpose: Implements idempotency by checking if the final state (snapshot) already exists.
# =====================================================================================

# =====================================================================================
# verify_docker_and_gpu_setup_inside_container()
#   Content:
#     - Log starting verification of Docker and GPU setup inside container CTID.
#
#     - # 1. Verify Direct GPU Access
#     - Log verifying direct GPU access by running nvidia-smi.
#     - Execute `pct exec "$CTID" -- nvidia-smi` and capture output and exit code.
#     - Print the output of `nvidia-smi` to the terminal/log for user visibility.
#     - If the exit code is non-zero, log a fatal error indicating direct GPU verification failed and call exit_script 4.
#     - Log direct GPU access verified.
#
#     - # 2. Verify Docker Info (including NVIDIA Runtime)
#     - Log verifying Docker information.
#     - Execute `pct exec "$CTID" -- docker info` and capture output and exit code.
#     - Print the output of `docker info` to the terminal/log for user visibility (focus on NVIDIA runtime section).
#     - If the exit code is non-zero, log a fatal error indicating Docker info verification failed and call exit_script 4.
#     - Log Docker information verified.
#
#     - # 3. Verify Docker Container with GPU Access
#     - Log verifying Docker container GPU access using a simple CUDA container.
#     - Define test image: TEST_IMAGE="nvidia/cuda:12.8.0-base-ubuntu24.04" (Use a lightweight, official image matching CUDA 12.8)
#     - Define test command: TEST_COMMAND="nvidia-smi" (Simple command to run inside the container)
#     - Execute: `pct exec "$CTID" -- docker run --rm --gpus all "$TEST_IMAGE" "$TEST_COMMAND"`
#     - Capture output and exit code.
#     - Print the output of the `docker run` command to the terminal/log.
#     - If the exit code is non-zero, log a fatal error indicating Docker GPU container verification failed and call exit_script 4.
#     - Log Docker container GPU access verified.
#
#     - Log Docker and GPU setup verification completed successfully inside container CTID.
#   Purpose: Confirms that both direct GPU access and Docker-with-GPU-access are functional inside the container.
# =====================================================================================

# =====================================================================================
# shutdown_container()
#   Content:
#     - Log initiating shutdown of container CTID.
#     - Execute: `pct shutdown "$CTID"`
#     - Capture exit code. If non-zero, log error and call exit_script 6.
#     - Implement a loop to wait for the container to reach 'stopped' status using `pct status "$CTID"`.
#         - Use a timeout and sleep interval.
#         - If timeout is exceeded before 'stopped', log error and call exit_script 6.
#     - Log container CTID shutdown successfully.
#   Purpose: Safely shuts down the container before creating the ZFS snapshot.
# =====================================================================================

# =====================================================================================
# create_docker_gpu_snapshot()
#   Content:
#     - Log creating ZFS snapshot 'docker-gpu-snapshot' for container CTID.
#     - Execute: `pct snapshot create "$CTID" "docker-gpu-snapshot"`
#     - Capture exit code.
#     - If the exit code is non-zero, log a fatal error indicating snapshot creation failed and call exit_script 5.
#     - If the exit code is 0, log successful creation of 'docker-gpu-snapshot'.
#   Purpose: Creates the ZFS snapshot for the Docker+GPU template hierarchy.
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
#         - Log a success message (e.g., "BaseTemplateDockerGPU CTID 903 setup and 'docker-gpu-snapshot' creation completed successfully." or "BaseTemplateDockerGPU CTID 903 'docker-gpu-snapshot' already exists, skipping setup.").
#     - If exit_code is non-zero:
#         - Log a failure message indicating the script encountered an error during setup/snapshot creation, specifying the stage if possible.
#     - Ensure logs are flushed.
#     - Exit the script with the provided exit_code.
#   Purpose: Provides a single point for script termination, ensuring final logging and correct exit status.
# =====================================================================================