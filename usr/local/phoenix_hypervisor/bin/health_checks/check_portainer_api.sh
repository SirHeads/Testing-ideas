#!/bin/bash
#
# File: check_portainer_api.sh
# Description: Health check script to verify Portainer API responsiveness.
#              It polls the /api/status endpoint and returns 0 on success, 1 on failure.
#
# Arguments:
#   $1 - Portainer IP address (e.g., 10.0.0.101)
#   $2 - Portainer HTTPS port (e.g., 9443)
#   $3 - Path to the CA certificate file (e.g., /persistent-storage/ssl/portainer.phoenix.local.crt)
#
# Returns:
#   0 if Portainer API is responsive, 1 otherwise.
#

set -e

# Source common utilities
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE}")" &> /dev/null && pwd)
# When executed on the hypervisor, the base directory is fixed.
PHOENIX_BASE_DIR="/usr/local/phoenix_hypervisor"
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

PORTAINER_IP="$1"
PORTAINER_PORT="$2"
CA_CERT_PATH="$3"

if [ -z "$PORTAINER_IP" ] || [ -z "$PORTAINER_PORT" ] || [ -z "$CA_CERT_PATH" ]; then
    log_error "Usage: $0 <portainer_ip> <portainer_port> <ca_cert_path>"
    exit 1
fi

PORTAINER_URL="https://${PORTAINER_IP}:${PORTAINER_PORT}/api/status"
MAX_ATTEMPTS=30
INTERVAL=10
ATTEMPTS=0

log_info "DEBUG: SCRIPT_DIR is ${SCRIPT_DIR}"
log_info "DEBUG: PHOENIX_BASE_DIR is ${PHOENIX_BASE_DIR}"
log_info "Checking Portainer API health at ${PORTAINER_URL} using certificate ${CA_CERT_PATH}..."

# Ensure the certificate file exists
if [ ! -f "$CA_CERT_PATH" ]; then
    log_error "CA certificate file not found at: ${CA_CERT_PATH}"
    exit 1
fi

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    if curl --silent --fail --cacert "$CA_CERT_PATH" "$PORTAINER_URL"; then
        log_info "Portainer API is responsive."
        exit 0
    else
        ATTEMPTS=$((ATTEMPTS + 1))
        log_warn "Portainer API not yet responsive. Retrying in ${INTERVAL} seconds... (Attempt ${ATTEMPTS}/${MAX_ATTEMPTS})"
        sleep "$INTERVAL"
    fi
done

log_error "Portainer API did not become responsive after ${MAX_ATTEMPTS} attempts."
exit 1