#!/bin/bash
#
# File: phoenix_hypervisor_setup_902.sh
# Description: Finalizes the setup for LXC container 902 (BaseTemplateDocker) and creates the Docker ZFS snapshot.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script performs final configuration steps for the BaseTemplateDocker LXC container (CTID 902).
# It installs/configures Docker Engine and the NVIDIA Container Toolkit inside the container,
# verifies the setup, and then shuts down the container to create the 'docker-snapshot' ZFS snapshot.
# This snapshot serves as the foundation for other Docker-dependent templates and containers.
#
# Usage: ./phoenix_hypervisor_setup_902.sh <CTID>
#   Example: ./phoenix_hypervisor_setup_902.sh 902
#
# Arguments:
#   $1 (CTID): The Container ID, expected to be 902 for BaseTemplateDocker.
#
# Requirements:
#   - Proxmox host environment with 'pct' command available.
#   - Container 902 must be created/cloned and accessible.
#   - jq (for potential JSON parsing if needed).
#   - phoenix_hypervisor_lxc_docker.sh must be available and functional.
#
# Exit Codes:
#   0: Success (Setup completed, snapshot created or already existed).
#   1: General error.
#   2: Invalid input arguments.
#   3: Container 902 does not exist or is not accessible.
#   4: Docker Engine/NVIDIA Container Toolkit installation/configuration failed.
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
#     - Calls install_and_configure_docker_in_container by calling the common script.
#     - Calls verify_docker_setup_inside_container (e.g., run docker info).
#     - Calls shutdown_container.
#     - Calls create_docker_snapshot.
#     - Calls start_container.
#     - Calls exit_script.
#   Purpose: Controls the overall flow of the BaseTemplateDocker setup and snapshot creation.
# =====================================================================================

# --- Main Script Execution Starts Here ---

# =====================================================================================
# parse_arguments()
#   Content:
#     - Check the number of command-line arguments. Expect exactly one (CTID=902).
#     - If incorrect number of arguments, log a usage error message and call exit_script 2.
#     - Assign the first argument to a variable CTID.
#     - Log the received CTID.
#   Purpose: Retrieves the CTID from the command-line arguments.
# =====================================================================================

# =====================================================================================
# validate_inputs()
#   Content:
#     - Validate that CTID is '902'. While flexible, this script is specifically for 902.
#         - If CTID is not '902', log a warning but continue (or error if strict).
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
#   Purpose: Performs a basic sanity check that the target BaseTemplateDocker container exists and is manageable.
# =====================================================================================

# =====================================================================================
# check_if_snapshot_exists()
#   Content:
#     - Log checking for the existence of the 'docker-snapshot'.
#     - Execute `pct snapshot list "$CTID"` and capture output.
#     - Parse the output (e.g., using `jq` or `grep`) to see if 'docker-snapshot' is listed.
#     - If 'docker-snapshot' exists:
#         - Log that the snapshot already exists, implying setup is complete or was previously done.
#         - Call exit_script 0. (Idempotency)
#     - If 'docker-snapshot' does not exist:
#         - Log that the snapshot needs to be created.
#         - Return/Continue to the next step.
#   Purpose: Implements idempotency by checking if the final state (snapshot) already exists.
# =====================================================================================

# =====================================================================================
# install_and_configure_docker_in_container()
#   Content:
#     - Log starting Docker Engine/NVIDIA Container Toolkit setup inside container CTID.
#     - Define path to the common Docker script: DOCKER_SCRIPT="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_docker.sh"
#     - Check if DOCKER_SCRIPT exists and is executable. Fatal error if not.
#     - Execute the common Docker script, passing CTID and necessary parameters (e.g., portainer_role="none"):
#         - Execute: "$DOCKER_SCRIPT" "$CTID" "none" # "none" for portainer_role
#         - Capture exit code.
#         - If the exit code is non-zero, log a fatal error indicating Docker setup failed and call exit_script 4.
#     - Log Docker Engine/NVIDIA Container Toolkit setup completed successfully inside container CTID.
#   Purpose: Delegates the task of installing and configuring Docker software to the common script.
# =====================================================================================

# =====================================================================================
# verify_docker_setup_inside_container()
#   Content:
#     - Log verifying Docker setup inside container CTID.
#     - Execute `pct exec "$CTID" -- docker info` and capture output and exit code.
#     - Print the output of `docker info` to the terminal/log for user visibility.
#     - If the exit code is non-zero, log a fatal error indicating verification failed and call exit_script 4.
#     - (Optional/Additional) Run a simple test container:
#         - Log running docker hello-world test.
#         - Execute: `pct exec "$CTID" -- docker run --rm hello-world`
#         - Capture exit code. If non-zero, log warning/error.
#     - Log Docker verification successful.
#   Purpose: Runs docker info (and optionally hello-world) inside the container to confirm Docker is running.
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
# create_docker_snapshot()
#   Content:
#     - Log creating ZFS snapshot 'docker-snapshot' for container CTID.
#     - Execute: `pct snapshot create "$CTID" "docker-snapshot"`
#     - Capture exit code.
#     - If the exit code is non-zero, log a fatal error indicating snapshot creation failed and call exit_script 5.
#     - If the exit code is 0, log successful creation of 'docker-snapshot'.
#   Purpose: Creates the ZFS snapshot for the Docker template hierarchy.
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
#         - Log a success message (e.g., "BaseTemplateDocker CTID 902 setup and 'docker-snapshot' creation completed successfully." or "BaseTemplateDocker CTID 902 'docker-snapshot' already exists, skipping setup.").
#     - If exit_code is non-zero:
#         - Log a failure message indicating the script encountered an error during setup/snapshot creation, specifying the stage if possible.
#     - Ensure logs are flushed.
#     - Exit the script with the provided exit_code.
#   Purpose: Provides a single point for script termination, ensuring final logging and correct exit status.
# =====================================================================================