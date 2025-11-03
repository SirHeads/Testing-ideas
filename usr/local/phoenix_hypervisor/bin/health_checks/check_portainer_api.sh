#!/bin/bash
#
# File: check_portainer_api.sh
# Description: This health check script verifies the full network and certificate chain
#              to the Portainer API endpoint by performing an authenticated API call.
#
# Version: 2.0.0
# Author: Roo

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)
source "$PHOENIX_BASE_DIR/bin/phoenix_hypervisor_common_utils.sh"
# Source the portainer-manager to get access to the get_portainer_jwt function
source "$PHOENIX_BASE_DIR/bin/managers/portainer-manager.sh"

# --- MAIN LOGIC ---
main() {
    log_info "--- Starting Portainer API Health Check (Authenticated) ---"

    local PORTAINER_HOSTNAME="portainer.internal.thinkheads.ai"
    local PORTAINER_URL="https://${PORTAINER_HOSTNAME}:443"
    local CA_CERT_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_ca.crt"

    # 1. Check if the CA certificate exists
    if [ ! -f "$CA_CERT_PATH" ]; then
        log_error "Health check failed: Root CA certificate not found at $CA_CERT_PATH."
        return 1
    fi

    # 2. Attempt to get a JWT
    log_info "Attempting to authenticate with Portainer to verify API health..."
    local JWT
    JWT=$(get_portainer_jwt)
    if [ -z "$JWT" ]; then
        log_error "Health check failed: Could not obtain Portainer JWT."
        return 1
    fi
    log_success "Successfully obtained Portainer JWT."

    # 3. Perform an authenticated API call
    log_info "Performing authenticated API call to /api/endpoints..."
    if ! curl -s --fail --cacert "$CA_CERT_PATH" \
              --resolve "${PORTAINER_HOSTNAME}:443:10.0.0.12" \
              -H "Authorization: Bearer ${JWT}" \
              "${PORTAINER_URL}/api/endpoints" > /dev/null; then
        log_error "Health check failed: Authenticated API call to /api/endpoints failed."
        return 1
    fi

    log_success "Portainer API is healthy and responding to authenticated requests."
    return 0
}

main "$@"