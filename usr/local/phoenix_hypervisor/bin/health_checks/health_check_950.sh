#!/bin/bash

#
# File: health_check_950.sh
#
# Description: This script performs a comprehensive health check for a vLLM service
#              running within a specific LXC container (e.g., CTID 950). It goes
#              beyond a simple port check by implementing both liveness and readiness
#              probes, which is a best practice for robust service validation.
#
#              - The Liveness Probe checks if the vLLM service is running and responsive.
#              - The Readiness Probe verifies that the AI model is fully loaded and
#                the service is ready to accept inference requests.
#
# Dependencies: - `phoenix_hypervisor_common_utils.sh` for logging and utilities.
#               - `jq` for parsing the `phoenix_lxc_configs.json` file.
#               - `curl` for making HTTP requests to the vLLM API.
#
# Inputs:
#   - $1 (CTID): The ID of the LXC container to be checked.
#
# Outputs:
#   - Exits with status 0 if both liveness and readiness probes succeed.
#   - Exits with a non-zero status and logs a fatal error if dependencies are
#     missing, configuration is not found, or if either probe fails after
#     multiple retry attempts.
#

# --- Source Common Utilities ---
# shellcheck source=/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh
source "/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh"

# --- Script Constants ---
readonly REQUIRED_COMMANDS=("jq" "curl")
readonly CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
readonly LIVENESS_RETRY_LIMIT=10
readonly LIVENESS_RETRY_INTERVAL=5
readonly READINESS_RETRY_LIMIT=5
readonly READINESS_RETRY_INTERVAL=10

# --- Function Definitions ---

#
# Function: liveness_probe
# Description: Performs a liveness check to confirm the vLLM service is running.
#              It repeatedly queries the /health endpoint until it gets a successful
#              response or the retry limit is reached.
# Arguments:
#   $1 - The container ID (CTID).
#   $2 - The port number of the vLLM service.
#
liveness_probe() {
    local ct_id=$1
    local port=$2
    local liveness_url="http://localhost:${port}/health"

    log_info "Starting liveness probe for container ${ct_id} on port ${port}..."
    for ((i=1; i<=LIVENESS_RETRY_LIMIT; i++)); do
        log_info "Liveness check attempt ${i}/${LIVENESS_RETRY_LIMIT}..."
        # Use curl to check the health endpoint. --fail causes it to exit with an error on non-200 status codes.
        if curl --silent --fail "${liveness_url}"; then
            log_info "Liveness probe successful for container ${ct_id}."
            return 0
        fi
        sleep "${LIVENESS_RETRY_INTERVAL}"
    done

    log_error "Liveness probe FAILED for container ${ct_id} after ${LIVENESS_RETRY_LIMIT} attempts."
    exit 3
}

#
# Function: readiness_probe
# Description: Performs a readiness check to confirm the vLLM model is loaded and
#              the service is ready for inference. It sends a sample request to the
#              chat completions endpoint and checks for a valid, non-error response.
# Arguments:
#   $1 - The container ID (CTID).
#   $2 - The port number of the vLLM service.
#   $3 - The name of the model being served.
#
readiness_probe() {
    local ct_id=$1
    local port=$2
    local model_name=$3
    local readiness_url="http://localhost:${port}/v1/chat/completions"

    log_info "Starting readiness probe for container ${ct_id} with model '${model_name}'..."
    for ((i=1; i<=READINESS_RETRY_LIMIT; i++)); do
        log_info "Readiness check attempt ${i}/${READINESS_RETRY_LIMIT}..."
        # Send a minimal, valid request to the completions endpoint.
        response=$(curl --silent --request POST "${readiness_url}" \
            --header 'Content-Type: application/json' \
            --data-raw "{
                \"model\": \"${model_name}\",
                \"messages\": [{\"role\": \"user\", \"content\": \"Sanity check\"}]
            }")

        # Use jq to check if the JSON response contains an "error" key. If it doesn't, the probe is successful.
        if ! echo "${response}" | jq -e 'has("error")' > /dev/null; then
            log_info "Readiness probe successful for container ${ct_id}."
            return 0
        fi
        sleep "${READINESS_RETRY_INTERVAL}"
    done

    log_error "Readiness probe FAILED for container ${ct_id} after ${READINESS_RETRY_LIMIT} attempts."
    log_error "The last response from the server was: ${response}"
    exit 4
}

# --- Main Script Logic ---

# 1. Dependency Check: Ensure all required command-line tools are available.
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "${cmd}" &> /dev/null; then
        log_fatal "Required command '${cmd}' is not installed. Please install it and try again."
    fi
done

# 2. Argument Parsing: Verify that a CTID was provided.
if [[ -z "$1" ]]; then
    log_fatal "Usage: $0 <CTID>"
    exit 2
fi
CTID=$1

# 3. Configuration Loading: Read the vLLM port and model name from the central config file.
if [[ ! -f "${CONFIG_FILE}" ]]; then
    log_fatal "Configuration file not found at ${CONFIG_FILE}."
    exit 1
fi

# Use jq to extract container-specific settings.
VLLM_PORT=$(jq -r ".lxc_configs.\"${CTID}\".vllm_port" "${CONFIG_FILE}")
VLLM_MODEL_NAME=$(jq -r ".lxc_configs.\"${CTID}\".vllm_served_model_name" "${CONFIG_FILE}")

# Validate that the required configuration values were found.
if [[ -z "${VLLM_PORT}" || "${VLLM_PORT}" == "null" ]]; then
    log_fatal "vLLM port is not configured for CTID ${CTID} in ${CONFIG_FILE}."
    exit 1
fi

if [[ -z "${VLLM_MODEL_NAME}" || "${VLLM_MODEL_NAME}" == "null" ]]; then
    log_fatal "vLLM served model name is not configured for CTID ${CTID} in ${CONFIG_FILE}."
    exit 1
fi

# 4. Execute Probes: Run the liveness and readiness checks in sequence.
log_info "Starting vLLM health check for container ${CTID}..."
liveness_probe "${CTID}" "${VLLM_PORT}"
readiness_probe "${CTID}" "${VLLM_PORT}" "${VLLM_MODEL_NAME}"

log_info "Health check for container ${CTID} completed successfully. The vLLM service is live and ready."
exit 0