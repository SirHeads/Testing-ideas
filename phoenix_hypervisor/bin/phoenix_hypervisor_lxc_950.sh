#!/bin/bash
#
# File: phoenix_hypervisor_setup_950.sh
# Description: Finalizes the setup for LXC container 950 (vllmQwen3Coder).
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script deploys and configures the specific vLLM Docker container for the
# lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-5bit model inside LXC container CTID 950.
# It pulls the vLLM image, runs the container with the specific model and tensor parallelism (2),
# mounts necessary volumes (including HuggingFace cache), sets environment variables (HF token),
# waits for the model to load, and verifies API accessibility.
# This is a final application container, cloned from 920's 'vllm-base-snapshot'.
#
# Usage: ./phoenix_hypervisor_setup_950.sh <CTID>
#   Example: ./phoenix_hypervisor_setup_950.sh 950
#
# Arguments:
#   $1 (CTID): The Container ID, expected to be 950 for vllmQwen3Coder.
#
# Requirements:
#   - Proxmox host environment with 'pct' command available.
#   - Container 950 must be created/cloned and accessible.
#   - jq (for JSON parsing).
#   - Container 950 is expected to be cloned from 920's 'vllm-base-snapshot'.
#   - Docker and NVIDIA drivers/toolkit must be functional inside container 950.
#   - Access to phoenix_lxc_configs.json and phoenix_hypervisor_config.json for configuration details.
#
# Exit Codes:
#   0: Success (vLLM Qwen3 Coder Server deployed/running, accessible).
#   1: General error.
#   2: Invalid input arguments.
#   3: Container 950 does not exist or is not accessible.
#   4: Docker is not functional inside container 950.
#   5: Failed to parse configuration files for required details.
#   6: vLLM Qwen3 Coder container deployment failed.
#   7: vLLM Qwen3 Coder verification (API accessibility) failed.

# =====================================================================================
# main()
#   Content:
#     - Entry point.
#     - Define hardcoded paths for config files (consistent with orchestrator):
#         - LXC_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
#         - HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"
#     - Calls parse_arguments to get the CTID.
#     - Calls validate_inputs (CTID).
#     - Calls check_container_exists.
#     - Calls check_if_vllm_qwen3_coder_already_running. If running, log and exit 0 (idempotency).
#     - Calls verify_docker_is_functional_inside_container.
#     - Calls parse_required_configuration_details (LXC/Hypervisor configs for IP, model, tensor size, HF token path).
#     - Calls deploy_vllm_qwen3_coder_container_inside_container.
#     - Calls wait_for_qwen3_model_initialization.
#     - Calls verify_vllm_qwen3_coder_api_accessibility.
#     - Calls exit_script.
#   Purpose: Controls the overall flow of the vllmQwen3Coder setup.
# =====================================================================================

# --- Main Script Execution Starts Here ---

# =====================================================================================
# parse_arguments()
#   Content:
#     - Check the number of command-line arguments. Expect exactly one (CTID=950).
#     - If incorrect number of arguments, log a usage error message and call exit_script 2.
#     - Assign the first argument to a variable CTID.
#     - Log the received CTID.
#   Purpose: Retrieves the CTID from the command-line arguments.
# =====================================================================================

# =====================================================================================
# validate_inputs()
#   Content:
#     - Validate that CTID is '950'. While flexible, this script is specifically for 950.
#         - If CTID is not '950', log a warning but continue (or error if strict).
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
#   Purpose: Performs a basic sanity check that the target vllmQwen3Coder container exists and is manageable.
# =====================================================================================

# =====================================================================================
# check_if_vllm_qwen3_coder_already_running()
#   Content:
#     - Log checking if the specific vLLM Qwen3 Coder container is already running inside CTID.
#     - Define expected container name: EXPECTED_CONTAINER_NAME="vllm_qwen3_coder" (or based on config if dynamic).
#     - Execute `pct exec "$CTID" -- docker ps --filter "name=$EXPECTED_CONTAINER_NAME" --format "{{.Names}}"` and capture output.
#     - Check if the output contains '$EXPECTED_CONTAINER_NAME'.
#     - If the container is found running:
#         - Log that the vLLM Qwen3 Coder Server is already running, setup is complete or was previously done.
#         - Call exit_script 0. (Idempotency)
#     - If the container is not found running:
#         - Log that the vLLM Qwen3 Coder Server needs to be deployed/configured.
#         - Return/Continue to the next step.
#   Purpose: Implements idempotency by checking if the specific service is already deployed and running.
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
# parse_required_configuration_details()
#   Content:
#     - Log parsing required configuration details from JSON files.
#
#     - # 1. Parse LXC Config for CTID 950
#     - Check if LXC_CONFIG_FILE exists. If not, log error and call exit_script 5.
#     - Use `jq` to extract details for CTID 950:
#         - CONTAINER_IP=$(jq -r --arg ctid "$CTID" '.lxc_configs[$ctid].network_config.ip | split("/")[0]' "$LXC_CONFIG_FILE")
#         - VLLM_MODEL=$(jq -r --arg ctid "$CTID" '.lxc_configs[$ctid].vllm_model' "$LXC_CONFIG_FILE") # Should resolve to lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-5bit
#         - VLLM_TENSOR_PARALLEL_SIZE=$(jq -r --arg ctid "$CTID" '.lxc_configs[$ctid].vllm_tensor_parallel_size' "$LXC_CONFIG_FILE")
#     - Log parsed LXC config details (IP, Model, Tensor Size).
#
#     - # 2. Parse Hypervisor Config for HF Token Path
#     - Check if HYPERVISOR_CONFIG_FILE exists. If not, log error and call exit_script 5.
#     - Use `jq` or `source` to get the HF token file path:
#         - HF_TOKEN_FILE_PATH=$(jq -r '.core_paths.hf_token_file' "$HYPERVISOR_CONFIG_FILE")
#         # OR, if sourcing the bash config is easier/more reliable here:
#         # source "$HYPERVISOR_CONFIG_FILE" # Requires it to be a valid bash script exporting vars
#         # HF_TOKEN_FILE_PATH="$PHOENIX_HF_TOKEN_FILE"
#     - Log parsed HF token file path.
#
#     - # 3. Validate Parsed Details
#     - Check if CONTAINER_IP, VLLM_MODEL, VLLM_TENSOR_PARALLEL_SIZE, HF_TOKEN_FILE_PATH are non-empty.
#     - If any are empty, log error and call exit_script 5.
#     - Log all required configuration details parsed and validated successfully.
#   Purpose: Extracts necessary configuration values (IP, model name, tensor size, HF token path) needed for deployment and verification.
# =====================================================================================

# =====================================================================================
# deploy_vllm_qwen3_coder_container_inside_container()
#   Content:
#     - Log deploying specific vLLM Qwen3 Coder Docker container inside container CTID.
#
#     - # 1. Prepare Deployment Parameters
#     - Define vLLM image: VLLM_IMAGE="vllm/vllm-openai:latest" (or specific version if preferred).
#     - Define container name: CONTAINER_NAME="vllm_qwen3_coder".
#     - Define port mapping: PORT_MAPPING="-p 8000:8000".
#     - Define GPU options: GPU_OPTIONS="--runtime nvidia --gpus all".
#     - Define IPC option: IPC_OPTION="--ipc=host".
#     - Define restart policy: RESTART_POLICY="--restart=always".
#     - Define volume mounts:
#         - HF Cache Volume: HF_VOLUME="-v ~/.cache/huggingface:/root/.cache/huggingface" (Standard path inside container)
#         - (Optional) If the HF token file needs to be mounted: HF_TOKEN_VOLUME="-v $HF_TOKEN_FILE_PATH:/root/.cache/huggingface/token:ro" (Mount RO)
#     - Define environment variables:
#         - HF Token Env Var: HF_ENV_VAR="-e HUGGING_FACE_HUB_TOKEN=$(cat $HF_TOKEN_FILE_PATH)" (Read token and pass as env var)
#         # OR if mounting the file: Skip this env var.
#     - Define the serve command:
#         - SERVE_CMD="vllm serve $VLLM_MODEL --tensor-parallel-size $VLLM_TENSOR_PARALLEL_SIZE"
#
#     - # 2. Construct and Execute Docker Run Command
#     - Log constructing and executing the docker run command for vLLM Qwen3 Coder.
#     - Construct the full `docker run` command string using the variables defined above.
#     - Example (Env Var Approach):
#         - FULL_RUN_CMD="docker run -d $PORT_MAPPING $GPU_OPTIONS $IPC_OPTION $RESTART_POLICY $HF_VOLUME $HF_ENV_VAR --name $CONTAINER_NAME $VLLM_IMAGE $SERVE_CMD"
#     - Example (Mounted Token File Approach):
#         - FULL_RUN_CMD="docker run -d $PORT_MAPPING $GPU_OPTIONS $IPC_OPTION $RESTART_POLICY $HF_VOLUME $HF_TOKEN_VOLUME --name $CONTAINER_NAME $VLLM_IMAGE $SERVE_CMD"
#     - Execute: `pct exec "$CTID" -- $FULL_RUN_CMD`
#     - Capture exit code.
#     - If the exit code is non-zero, log a fatal error indicating vLLM container deployment failed and call exit_script 6.
#     - If the exit code is 0, log successful initiation of vLLM Qwen3 Coder container deployment.
#   Purpose: Runs the official vLLM Docker container inside the LXC with the specific Qwen3 model, tensor parallelism, and HF token configuration.
# =====================================================================================

# =====================================================================================
# wait_for_qwen3_model_initialization()
#   Content:
#     - Log waiting for Qwen3 Coder model to initialize inside container CTID.
#     - Define timeout (e.g., 300s/5mins - model is large) and polling interval (e.g., 15s).
#     - Initialize counter/end time.
#     - Implement while loop:
#         - Check if the vLLM container is running: `pct exec "$CTID" -- docker ps --filter "name=vllm_qwen3_coder" --format "{{.Names}}"`.
#         - If running, attempt to check logs for readiness indicator:
#             - `pct exec "$CTID" -- docker logs vllm_qwen3_coder 2>&1 | grep -q "Uvicorn running on"`
#             - If grep succeeds (exit code 0), model/server is likely ready. Break loop.
#         - Sleep for interval.
#         - Check if timeout exceeded. If so, log timeout error, return failure code.
#     - If loop exits successfully, log Qwen3 Coder model initialized.
#     - Return appropriate exit code (0 for ready, non-zero for timeout/error).
#   Purpose: Ensures the large Qwen3 Coder model has loaded and the vLLM service is responsive before declaring deployment success.
# =====================================================================================

# =====================================================================================
# verify_vllm_qwen3_coder_api_accessibility()
#   Content:
#     - Log verifying vLLM Qwen3 Coder API accessibility.
#     - Perform a basic connectivity and response check from inside the container:
#         - Define curl command:
#             - CURL_CMD='curl -X POST http://localhost:8000/v1/chat/completions -H "Content-Type: application/json" -d "{\"model\": \"'$VLLM_MODEL'\", \"messages\": [{\"role\": \"user\", \"content\": \"What is the capital of France?\"}]}"'
#         - Execute `pct exec "$CTID" -- bash -c "$CURL_CMD"` and capture output (JSON response) and exit code.
#         - Print the JSON output of the curl command to the terminal/log.
#         - If the exit code is non-zero, log error and call exit_script 7.
#         - If the exit code is 0:
#             - Parse the JSON output (using `jq`) to extract the assistant's reply content.
#             - Check if the extracted content contains a relevant word (e.g., "Paris") (case-insensitive).
#                 - If a relevant word is found, log successful verification.
#                 - If not found, log a warning that the model reply didn't contain the expected word, but might still be a valid response. Continue or consider it a soft failure? (Log warning and continue for now).
#             - If parsing failed, log error and call exit_script 7.
#     - Log vLLM Qwen3 Coder API verified as accessible at http://$CONTAINER_IP:8000/v1/chat/completions.
#   Purpose: Confirms that the vLLM API endpoint for the Qwen3 model is reachable and responding correctly from within the container.
# =====================================================================================

# =====================================================================================
# exit_script(exit_code)
#   Content:
#     - Accept an integer exit_code.
#     - If exit_code is 0:
#         - Log a success message (e.g., "vllmQwen3Coder CTID 950 setup completed successfully. Model API accessible at http://$CONTAINER_IP:8000/v1/chat/completions." or "vllmQwen3Coder CTID 950 is already running.").
#     - If exit_code is non-zero:
#         - Log a failure message indicating the script encountered an error during setup/verification, specifying the stage if possible.
#     - Ensure logs are flushed.
#     - Exit the script with the provided exit_code.
#   Purpose: Provides a single point for script termination, ensuring final logging and correct exit status.
# =====================================================================================