#!/bin/bash
#
# File: phoenix_hypervisor_setup_900.sh
# Description: Finalizes the setup for LXC container 900 (BaseTemplate) and creates the base ZFS snapshot.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script performs final configuration steps for the BaseTemplate LXC container (CTID 900).
# It installs essential base packages, performs basic OS hardening/configuration,
# and then shuts down the container to create the 'base-snapshot' ZFS snapshot.
# This snapshot serves as the foundation for all other templates and containers.
#
# Usage: ./phoenix_hypervisor_setup_900.sh <CTID>
#   Example: ./phoenix_hypervisor_setup_900.sh 900
#
# Arguments:
#   $1 (CTID): The Container ID, expected to be 900 for BaseTemplate.
#
# Requirements:
#   - Proxmox host environment with 'pct' command available.
#   - Container 900 must be created and accessible.
#   - jq (for potential JSON parsing if needed).
#
# Exit Codes:
#   0: Success (Setup completed, snapshot created or already existed).
#   1: General error.
#   2: Invalid input arguments.
#   3: Container 900 does not exist or is not accessible.
#   4: OS update/installation failed.
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
#     - Calls perform_base_os_setup inside the container.
#     - Calls shutdown_container.
#     - Calls create_base_snapshot.
#     - Calls start_container.
#     - Calls exit_script.
#   Purpose: Controls the overall flow of the BaseTemplate setup and snapshot creation.
# =====================================================================================

# --- Main Script Execution Starts Here ---

# =====================================================================================
# parse_arguments()
#   Content:
#     - Check the number of command-line arguments. Expect exactly one (CTID=900).
#     - If incorrect number of arguments, log a usage error message and call exit_script 2.
#     - Assign the first argument to a variable CTID.
#     - Log the received CTID.
#   Purpose: Retrieves the CTID from the command-line arguments.
# =====================================================================================

# =====================================================================================
# validate_inputs()
#   Content:
#     - Validate that CTID is '900'. While flexible, this script is specifically for 900.
#         - If CTID is not '900', log a warning but continue (or error if strict).
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
#   Purpose: Performs a basic sanity check that the target BaseTemplate container exists and is manageable.
# =====================================================================================

# =====================================================================================
# check_if_snapshot_exists()
#   Content:
#     - Log checking for the existence of the 'base-snapshot'.
#     - Execute `pct snapshot list "$CTID"` and capture output.
#     - Parse the output (e.g., using `jq` or `grep`) to see if 'base-snapshot' is listed.
#     - If 'base-snapshot' exists:
#         - Log that the snapshot already exists, implying setup is complete or was previously done.
#         - Call exit_script 0. (Idempotency)
#     - If 'base-snapshot' does not exist:
#         - Log that the snapshot needs to be created.
#         - Return/Continue to the next step.
#   Purpose: Implements idempotency by checking if the final state (snapshot) already exists.
# =====================================================================================

# =====================================================================================
# perform_base_os_setup()
#   Content:
#     - Log starting base OS setup inside container CTID.
#     - Define a list of essential packages: (e.g., "curl wget vim htop jq git rsync s-tui")
#     - Update package lists inside the container:
#         - Execute: `pct exec "$CTID" -- apt-get update`
#         - Capture exit code. If non-zero, log error and call exit_script 4.
#     - Upgrade essential packages inside the container:
#         - Execute: `pct exec "$CTID" -- apt-get upgrade -y`
#         - Capture exit code. If non-zero, log error and call exit_script 4.
#     - Install essential utility packages inside the container:
#         - Execute: `pct exec "$CTID" -- apt-get install -y <package_list>`
#         - Capture exit code. If non-zero, log error and call exit_script 4.
#     - (Optional) Perform basic OS hardening or configuration steps inside the container if needed.
#         - Example: `pct exec "$CTID" -- command_to_configure_something`
#     - Log base OS setup completed successfully.
#   Purpose: Installs fundamental tools and performs basic configuration inside the BaseTemplate container.
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
# create_base_snapshot()
#   Content:
#     - Log creating ZFS snapshot 'base-snapshot' for container CTID.
#     - Execute: `pct snapshot create "$CTID" "base-snapshot"`
#     - Capture exit code.
#     - If the exit code is non-zero, log a fatal error indicating snapshot creation failed and call exit_script 5.
#     - If the exit code is 0, log successful creation of 'base-snapshot'.
#   Purpose: Creates the foundational ZFS snapshot for the template hierarchy.
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
#         - Log a success message (e.g., "BaseTemplate CTID 900 setup and 'base-snapshot' creation completed successfully." or "BaseTemplate CTID 900 'base-snapshot' already exists, skipping setup.").
#     - If exit_code is non-zero:
#         - Log a failure message indicating the script encountered an error during setup/snapshot creation, specifying the stage if possible.
#     - Ensure logs are flushed.
#     - Exit the script with the provided exit_code.
#   Purpose: Provides a single point for script termination, ensuring final logging and correct exit status.
# =====================================================================================