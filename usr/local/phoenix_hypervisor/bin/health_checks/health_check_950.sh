#!/bin/bash

# Source the common utilities
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

# Performs the liveness probe to check if the vLLM service is running
liveness_probe() {
    local ct_id=$1
    local port=$2
    local liveness_url="http://localhost:${port}/health"

    log_info "Starting liveness probe for container ${ct_id}..."
    for ((i=1; i<=LIVENESS_RETRY_LIMIT; i++)); do
        log_info "Liveness check attempt ${i}/${LIVENESS_RETRY_LIMIT}..."
        if curl --silent --fail "${liveness_url}"; then
            log_info "Liveness probe successful for container ${ct_id}."
            return 0
        fi
        sleep "${LIVENESS_RETRY_INTERVAL}"
    done

    log_error "Liveness probe failed for container ${ct_id} after ${LIVENESS_RETRY_LIMIT} attempts."
    exit 3
}

# Performs the readiness probe to check if the model is loaded and ready
readiness_probe() {
    local ct_id=$1
    local port=$2
    local model_name=$3
    local readiness_url="http://localhost:${port}/v1/chat/completions"

    log_info "Starting readiness probe for container ${ct_id}..."
    for ((i=1; i<=READINESS_RETRY_LIMIT; i++)); do
        log_info "Readiness check attempt ${i}/${READINESS_RETRY_LIMIT}..."
        response=$(curl --silent --request POST "${readiness_url}" \
            --header 'Content-Type: application/json' \
            --data-raw "{
                \"model\": \"${model_name}\",
                \"messages\": [{\"role\": \"user\", \"content\": \"Sanity check\"}]
            }")

        if ! echo "${response}" | jq -e 'has("error")' > /dev/null; then
            log_info "Readiness probe successful for container ${ct_id}."
            return 0
        fi
        sleep "${READINESS_RETRY_INTERVAL}"
    done

    log_error "Readiness probe failed for container ${ct_id} after ${READINESS_RETRY_LIMIT} attempts."
    log_error "Last response: ${response}"
    exit 4
}

# --- Main Script Logic ---

# Check for required commands
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "${cmd}" &> /dev/null; then
        log_fatal "Required command '${cmd}' is not installed. Please install it and try again."
    fi
done

# Argument parsing
if [[ -z "$1" ]]; then
    log_fatal "Usage: $0 <CTID>"
    exit 2
fi
CTID=$1

# Configuration loading
if [[ ! -f "${CONFIG_FILE}" ]]; then
    log_fatal "Configuration file not found at ${CONFIG_FILE}."
    exit 1
fi

VLLM_PORT=$(jq -r ".lxc_configs.\"${CTID}\".vllm_port" "${CONFIG_FILE}")
VLLM_MODEL_NAME=$(jq -r ".lxc_configs.\"${CTID}\".vllm_served_model_name" "${CONFIG_FILE}")

if [[ -z "${VLLM_PORT}" || "${VLLM_PORT}" == "null" ]]; then
    log_fatal "vLLM port not configured for CTID ${CTID} in ${CONFIG_FILE}."
    exit 1
fi

if [[ -z "${VLLM_MODEL_NAME}" || "${VLLM_MODEL_NAME}" == "null" ]]; then
    log_fatal "vLLM model name not configured for CTID ${CTID} in ${CONFIG_FILE}."
    exit 1
fi

# Execute probes
liveness_probe "${CTID}" "${VLLM_PORT}"
readiness_probe "${CTID}" "${VLLM_PORT}" "${VLLM_MODEL_NAME}"

log_info "Health check for container ${CTID} completed successfully."
exit 0