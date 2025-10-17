#!/bin/bash
#
# File: check_portainer_api.sh
# Description: This script performs a health check on the Portainer API to ensure it is responsive.
#
# Inputs:
#   None. It reads all necessary configuration from the central phoenix_hypervisor_config.json.
#
# Version: 1.1.0
# Author: Phoenix Hypervisor Team
#

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
HOSTNAME=$(get_global_config_value '.portainer_api.portainer_hostname')
PORT="443" # Always check against the public-facing Nginx proxy port
CA_CERT_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_ca.crt"
MAX_RETRIES=12
RETRY_DELAY=10

# --- Main Health Check Logic ---
log_info "Performing health check on Portainer API at https://${HOSTNAME}:${PORT}..."

# Wait for the CA certificate to exist
log_info "Waiting for CA certificate to become available at ${CA_CERT_PATH}..."
for ((i=1; i<=MAX_RETRIES; i++)); do
    if [ -f "$CA_CERT_PATH" ]; then
        log_info "CA certificate found."
        break
    fi
    log_warn "Attempt ${i}/${MAX_RETRIES}: CA certificate not found. Retrying in ${RETRY_DELAY} seconds..."
    sleep "$RETRY_DELAY"
done

if [ ! -f "$CA_CERT_PATH" ]; then
    log_fatal "CA certificate not found at ${CA_CERT_PATH} after ${MAX_RETRIES} attempts."
fi

for ((i=1; i<=MAX_RETRIES; i++)); do
    log_info "Attempt ${i}/${MAX_RETRIES}: Checking Portainer API status..."
    response=$(curl -s --cacert "$CA_CERT_PATH" "https://${HOSTNAME}:${PORT}/api/status" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ] && echo "$response" | jq -e '.Version' > /dev/null; then
        log_success "Portainer API is responsive (found version field)."
        exit 0
    else
        log_warn "Portainer API is not yet responsive. Curl exit code: $exit_code, Response: $response"
        log_warn "Retrying in ${RETRY_DELAY} seconds..."
        sleep "$RETRY_DELAY"
    fi
done

log_fatal "Portainer API health check failed after ${MAX_RETRIES} attempts."