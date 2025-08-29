#!/bin/bash
#
# File: phoenix_hypervisor_setup_910.sh
# Description: Finalizes the setup for LXC container 910 (Portainer Server).
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script deploys and configures the Portainer Server application inside
# the LXC container CTID 910. It pulls the Portainer CE Docker image, runs the
# Portainer container with necessary configurations (volume mounts, port mappings),
# and verifies that the service is running and accessible.
#
# Usage: ./phoenix_hypervisor_setup_910.sh <CTID>
#   Example: ./phoenix_hypervisor_setup_910.sh 910
#
# Arguments:
#   $1 (CTID): The Container ID, expected to be 910 for Portainer.
#
# Requirements:
#   - Proxmox host environment with 'pct' command available.
#   - Container 910 must be created/cloned and accessible.
#   - jq (for potential JSON parsing if needed).
#   - Container 910 is expected to be cloned from 902's 'docker-snapshot'.
#   - Docker must be functional inside container 910.
#
# Exit Codes:
#   0: Success (Portainer Server deployed/running, accessible).
#   1: General error.
#   2: Invalid input arguments.
#   3: Container 910 does not exist or is not accessible.
#   4: Docker is not functional inside container 910.
#   5: Portainer Server container deployment failed.
#   6: Portainer Server verification (accessibility) failed.

# =====================================================================================
# main()
#   Content:
#     - Entry point.
#     - Calls parse_arguments to get the CTID.
#     - Calls validate_inputs (CTID).
#     - Calls check_container_exists.
#     - Calls check_if_portainer_already_running. If running, log and exit 0 (idempotency).
#     - Calls verify_docker_is_functional_inside_container.
#     - Calls deploy_portainer_server_container_inside_container.
#     - Calls wait_for_portainer_initialization.
#     - Calls verify_portainer_server_accessibility.
#     - Calls exit_script.
#   Purpose: Controls the overall flow of the Portainer Server setup.
# =====================================================================================

# --- Main Script Execution Starts Here ---

# =====================================================================================
# parse_arguments()
#   Content:
#     - Check the number of command-line arguments. Expect exactly one (CTID=910).
#     - If incorrect number of arguments, log a usage error message and call exit_script 2.
#     - Assign the first argument to a variable CTID.
#     - Log the received CTID.
#   Purpose: Retrieves the CTID from the command-line arguments.
# =====================================================================================

# =====================================================================================
# validate_inputs()
#   Content:
#     - Validate that CTID is '910'. While flexible, this script is specifically for 910.
#         - If CTID is not '910', log a warning but continue (or error if strict).
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
#   Purpose: Performs a basic sanity check that the target Portainer container exists and is manageable.
# =====================================================================================

# =====================================================================================
# check_if_portainer_already_running()
#   Content:
#     - Log checking if Portainer Server container is already running inside CTID.
#     - Execute `pct exec "$CTID" -- docker ps --filter "name=portainer" --format "{{.Names}}"` and capture output.
#     - Check if the output contains 'portainer' (or the specific container name used).
#     - If the Portainer container is found running:
#         - Log that Portainer Server is already running, setup is complete or was previously done.
#         - Call exit_script 0. (Idempotency)
#     - If the Portainer container is not found running:
#         - Log that Portainer Server needs to be deployed/configured.
#         - Return/Continue to the next step.
#   Purpose: Implements idempotency by checking if the Portainer service is already deployed and running.
# =====================================================================================

# =====================================================================================
# verify_docker_is_functional_inside_container()
#   Content:
#     - Log verifying Docker functionality inside container CTID.
#     - Execute `pct exec "$CTID" -- docker info > /dev/null 2>&1`.
#     - Capture the exit code.
#     - If the exit code is non-zero, log a fatal error indicating Docker is not functional inside the container and call exit_script 4.
#     - If the exit code is 0, log Docker verified as functional inside container CTID.
#   Purpose: Ensures the prerequisite Docker environment inside the container is working before proceeding.
# =====================================================================================

# =====================================================================================
# deploy_portainer_server_container_inside_container()
#   Content:
#     - Log deploying Portainer Server Docker container inside container CTID.
#     - Define Portainer image: PORTAINER_IMAGE="portainer/portainer-ce:latest" (or a specific version).
#     - Define container name: CONTAINER_NAME="portainer".
#     - Define port mappings: PORTS="-p 9443:9443 -p 9001:9001" (UI and Agent port).
#     - Define volume mounts:
#         - Docker socket: DOCKER_SOCKET_VOLUME="-v /var/run/docker.sock:/var/run/docker.sock"
#         - Data volume: DATA_VOLUME="-v portainer_data:/data"
#     - Define restart policy: RESTART_POLICY="--restart=always"
#     - Define command (if needed for initial password): COMMAND="" (Leave empty for now, or add --admin-password if setting it via CLI is straightforward).
#     - Construct the full `docker run` command.
#     - Execute: `pct exec "$CTID" -- docker run -d $PORTS $DOCKER_SOCKET_VOLUME $DATA_VOLUME $RESTART_POLICY --name $CONTAINER_NAME $PORTAINER_IMAGE $COMMAND`
#     - Capture exit code.
#     - If the exit code is non-zero, log a fatal error indicating Portainer container deployment failed and call exit_script 5.
#     - If the exit code is 0, log successful initiation of Portainer Server container deployment.
#   Purpose: Runs the official Portainer CE Docker container inside the LXC with the required configuration.
# =====================================================================================

# =====================================================================================
# wait_for_portainer_initialization()
#   Content:
#     - Log waiting for Portainer Server to initialize inside container CTID.
#     - Define timeout (e.g., 60s) and polling interval (e.g., 5s).
#     - Initialize counter/end time.
#     - Implement while loop:
#         - Check if the Portainer container is running: `pct exec "$CTID" -- docker ps --filter "name=portainer" --format "{{.Names}}"`.
#         - If running, attempt a basic connectivity check (e.g., `pct exec "$CTID" -- curl -k -s -o /dev/null -w "%{http_code}" https://localhost:9443`).
#         - If curl returns 200 or a reasonable code indicating the web server is responding, break loop.
#         - If not ready, sleep for interval.
#         - Check if timeout exceeded. If so, log timeout error, return failure code.
#     - If loop exits successfully, log Portainer Server initialized.
#     - Return appropriate exit code (0 for ready, non-zero for timeout/error).
#   Purpose: Ensures the Portainer service inside the container has started and is responsive before declaring success.
# =====================================================================================

# =====================================================================================
# verify_portainer_server_accessibility()
#   Content:
#     - Log verifying Portainer Server accessibility.
#     - Determine the container's IP address (e.g., by parsing config or assuming 10.0.0.99 for CTID 910).
#         - CONTAINER_IP="10.0.0.99" (Hardcoded based on CTID 910's config for now).
#     - Perform a basic connectivity check from the Proxmox host:
#         - Execute `curl -k -s -o /dev/null -w "%{http_code}" https://$CONTAINER_IP:9443`.
#         - Capture the HTTP status code.
#     - Check if the status code is 200 (OK) or 401/403 (Unauthorized/Forbidden, indicating the server is running and enforcing auth).
#     - If status code is acceptable:
#         - Log Portainer Server is accessible at https://$CONTAINER_IP:9443. Initial admin password is 'TestPhoenix'.
#     - If status code is not acceptable (e.g., 000, 404, 5xx):
#         - Log a fatal error indicating Portainer Server is not accessible and call exit_script 6.
#   Purpose: Confirms that the Portainer web UI is reachable from the network.
# =====================================================================================

# =====================================================================================
# exit_script(exit_code)
#   Content:
#     - Accept an integer exit_code.
#     - If exit_code is 0:
#         - Log a success message (e.g., "Portainer Server CTID 910 setup completed successfully. Accessible at https://10.0.0.99:9443. Initial password is 'TestPhoenix'." or "Portainer Server CTID 910 is already running.").
#     - If exit_code is non-zero:
#         - Log a failure message indicating the script encountered an error during setup/verification, specifying the stage if possible.
#     - Ensure logs are flushed.
#     - Exit the script with the provided exit_code.
#   Purpose: Provides a single point for script termination, ensuring final logging and correct exit status.
# =====================================================================================