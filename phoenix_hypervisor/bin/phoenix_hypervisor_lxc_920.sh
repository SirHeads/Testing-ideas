#!/bin/bash
#
# File: phoenix_hypervisor_setup_920.sh
# Description: Finalizes the setup for LXC container 920 (BaseTemplateVLLM) and creates the vLLM ZFS snapshot.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script performs final configuration steps for the BaseTemplateVLLM LXC container (CTID 920).
# It verifies that Docker Engine, the NVIDIA Container Toolkit, and direct GPU access (inherited/cloned from 903)
# are correctly configured and functional inside the container. It then pulls the official vLLM Docker image,
# runs a test vLLM container using a small model, verifies API access via curl (checking for 'Paris'),
# cleans up the test container, and finally shuts down the container to create the 'vllm-base-snapshot' ZFS snapshot.
# This snapshot serves as the foundation for other vLLM-dependent templates and containers.
#
# Usage: ./phoenix_hypervisor_setup_920.sh <CTID>
#   Example: ./phoenix_hypervisor_setup_920.sh 920
#
# Arguments:
#   $1 (CTID): The Container ID, expected to be 920 for BaseTemplateVLLM.
#
# Requirements:
#   - Proxmox host environment with 'pct' command available.
#   - Container 920 must be created/cloned and accessible.
#   - jq (for potential JSON parsing if needed).
#   - Container 920 is expected to be cloned from 903's 'docker-gpu-snapshot'.
#   - Docker and NVIDIA drivers/toolkit must be functional inside container 920.
#
# Exit Codes:
#   0: Success (Setup completed, snapshot created or already existed).
#   1: General error.
#   2: Invalid input arguments.
#   3: Container 920 does not exist or is not accessible.
#   4: Prerequisite Docker/NVIDIA verification inside container failed.
#   5: vLLM test deployment or API verification failed.
#   6: Container shutdown/start failed.
#   7: Snapshot creation failed.

# =====================================================================================
# main()
#   Content:
#     - Entry point.
#     - Calls parse_arguments to get the CTID.
#     - Calls validate_inputs (CTID).
#     - Calls check_container_exists.
#     - Calls check_if_snapshot_exists. If snapshot exists, log and exit 0 (idempotency).
#     - Calls verify_prerequisites_inside_container (Docker, NVIDIA).
#     - Calls deploy_and_test_vllm_inside_container.
#     - Calls shutdown_container.
#     - Calls create_vllm_base_snapshot.
#     - Calls start_container.
#     - Calls exit_script.
#   Purpose: Controls the overall flow of the BaseTemplateVLLM setup and snapshot creation.
# =====================================================================================

# --- Main Script Execution Starts Here ---

# =====================================================================================
# parse_arguments()
#   Content:
#     - Check the number of command-line arguments. Expect exactly one (CTID=920).
#     - If incorrect number of arguments, log a usage error message and call exit_script 2.
#     - Assign the first argument to a variable CTID.
#     - Log the received CTID.
#   Purpose: Retrieves the CTID from the command-line arguments.
# =====================================================================================

# =====================================================================================
# validate_inputs()
#   Content:
#     - Validate that CTID is '920'. While flexible, this script is specifically for 920.
#         - If CTID is not '920', log a warning but continue (or error if strict).
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
#   Purpose: Performs a basic sanity check that the target BaseTemplateVLLM container exists and is manageable.
# =====================================================================================

# =====================================================================================
# check_if_snapshot_exists()
#   Content:
#     - Log checking for the existence of the 'vllm-base-snapshot'.
#     - Execute `pct snapshot list "$CTID"` and capture output.
#     - Parse the output (e.g., using `jq` or `grep`) to see if 'vllm-base-snapshot' is listed.
#     - If 'vllm-base-snapshot' exists:
#         - Log that the snapshot already exists, implying setup is complete or was previously done.
#         - Call exit_script 0. (Idempotency)
#     - If 'vllm-base-snapshot' does not exist:
#         - Log that the snapshot needs to be created.
#         - Return/Continue to the next step.
#   Purpose: Implements idempotency by checking if the final state (snapshot) already exists.
# =====================================================================================

# =====================================================================================
# verify_prerequisites_inside_container()
#   Content:
#     - Log verifying prerequisites (Docker, NVIDIA) inside container CTID.
#
#     - # 1. Verify Docker Info (including NVIDIA Runtime)
#     - Log verifying Docker information inside CTID.
#     - Execute `pct exec "$CTID" -- docker info` and capture output and exit code.
#     - Print relevant parts of `docker info` output to the terminal/log (focus on NVIDIA runtime section).
#     - If the exit code is non-zero, log a fatal error indicating Docker verification failed and call exit_script 4.
#     - Log Docker information verified inside CTID.
#
#     - # 2. Verify Direct GPU Access
#     - Log verifying direct GPU access by running nvidia-smi inside CTID.
#     - Execute `pct exec "$CTID" -- nvidia-smi` and capture output and exit code.
#     - Print the output of `nvidia-smi` to the terminal/log for user visibility.
#     - If the exit code is non-zero, log a fatal error indicating direct GPU verification failed and call exit_script 4.
#     - Log direct GPU access verified inside CTID.
#
#     - Log all prerequisites verified successfully inside container CTID.
#   Purpose: Confirms that the inherited Docker and NVIDIA setups are functional inside the container before proceeding with vLLM-specific steps.
# =====================================================================================

# =====================================================================================
# deploy_and_test_vllm_inside_container()
#   Content:
#     - Log starting vLLM test deployment and verification inside container CTID.
#
#     - # 1. Pull Official vLLM Docker Image
#     - Log pulling official vLLM Docker image.
#     - Define image: VLLM_IMAGE="vllm/vllm-openai:latest"
#     - Execute: `pct exec "$CTID" -- docker pull "$VLLM_IMAGE"`
#     - Capture exit code. If non-zero, log error and call exit_script 5.
#     - Log vLLM image pulled successfully.
#
#     - # 2. Run Test vLLM Container
#     - Log running test vLLM container.
#     - Define test model: TEST_MODEL="Qwen/Qwen2.5-Coder-0.5B-Instruct-GPTQ-Int8" (As discussed)
#     - Define container name: TEST_CONTAINER_NAME="vllm_test_container"
#     - Define run command:
#         - RUN_OPTS="--runtime nvidia --gpus all -p 8000:8000 --ipc=host --name $TEST_CONTAINER_NAME"
#         - MODEL_ARG="--model $TEST_MODEL"
#         - FULL_RUN_CMD="docker run -d $RUN_OPTS $VLLM_IMAGE $MODEL_ARG"
#     - Execute: `pct exec "$CTID" -- $FULL_RUN_CMD`
#     - Capture exit code. If non-zero, log error and call exit_script 5.
#     - Log test vLLM container started.
#
#     - # 3. Wait for Model Load
#     - Log waiting for test model to load inside CTID.
#     - Define timeout (e.g., 120s) and polling interval (e.g., 10s).
#     - Initialize counter/end time.
#     - Implement while loop:
#         - Check if logs indicate readiness or attempt a simple curl: `pct exec "$CTID" -- docker logs $TEST_CONTAINER_NAME 2>&1 | grep -q "Uvicorn running on"`
#         - If grep succeeds (exit code 0), model/server is likely ready. Break loop.
#         - Sleep for interval.
#         - Check if timeout exceeded. If so, log timeout warning but proceed to curl test (it might still work or fail gracefully).
#     - Log waited for model load (or timed out).
#
#     - # 4. Verify API Access via Curl (Check for 'Paris')
#     - Log verifying vLLM API access via curl inside CTID.
#     - Define curl command:
#         - CURL_CMD='curl -X POST http://localhost:8000/v1/chat/completions -H "Content-Type: application/json" -d "{\"model\": \"'$TEST_MODEL'\", \"messages\": [{\"role\": \"user\", \"content\": \"What is the capital of France?\"}]}"'
#     - Execute: `pct exec "$CTID" -- bash -c "$CURL_CMD"` and capture output (JSON response) and exit code.
#     - Print the JSON output of the curl command to the terminal/log.
#     - If the exit code is non-zero, log error and call exit_script 5.
#     - Parse the JSON output (using `jq`) to extract the assistant's reply content.
#     - Check if the extracted content contains the word "Paris" (case-insensitive).
#         - If "Paris" is found, log successful verification.
#         - If "Paris" is NOT found, log a warning that the model reply didn't contain the expected word, but might still be a valid response. Continue or consider it a soft failure? (For now, log warning and continue).
#     - If the exit code from curl was 0 but parsing failed, log error and call exit_script 5.
#
#     - # 5. Clean Up Test Container
#     - Log stopping and removing test vLLM container inside CTID.
#     - Execute: `pct exec "$CTID" -- docker stop "$TEST_CONTAINER_NAME"`
#     - Capture exit code. Log outcome.
#     - Execute: `pct exec "$CTID" -- docker rm "$TEST_CONTAINER_NAME"`
#     - Capture exit code. Log outcome.
#     - Log test container cleaned up inside CTID.
#
#     - Log vLLM test deployment and verification completed successfully inside container CTID.
#   Purpose: Deploys a test vLLM container using a small model, waits for it, tests its API with curl (checking for 'Paris'), and cleans up the test container.
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
# create_vllm_base_snapshot()
#   Content:
#     - Log creating ZFS snapshot 'vllm-base-snapshot' for container CTID.
#     - Execute: `pct snapshot create "$CTID" "vllm-base-snapshot"`
#     - Capture exit code.
#     - If the exit code is non-zero, log a fatal error indicating snapshot creation failed and call exit_script 7.
#     - If the exit code is 0, log successful creation of 'vllm-base-snapshot'.
#   Purpose: Creates the ZFS snapshot for the vLLM template hierarchy.
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
#         - Log a success message (e.g., "BaseTemplateVLLM CTID 920 setup and 'vllm-base-snapshot' creation completed successfully." or "BaseTemplateVLLM CTID 920 'vllm-base-snapshot' already exists, skipping setup.").
#     - If exit_code is non-zero:
#         - Log a failure message indicating the script encountered an error during setup/snapshot creation, specifying the stage if possible.
#     - Ensure logs are flushed.
#     - Exit the script with the provided exit_code.
#   Purpose: Provides a single point for script termination, ensuring final logging and correct exit status.
# =====================================================================================