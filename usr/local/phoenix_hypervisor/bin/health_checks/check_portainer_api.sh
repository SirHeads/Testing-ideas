#!/bin/bash
#
# File: check_portainer_api.sh
# Description: This health check script verifies the full network and certificate chain
#              to the Portainer API endpoint.
#
# Version: 1.0.0
# Author: Roo

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)
source "$PHOENIX_BASE_DIR/bin/phoenix_hypervisor_common_utils.sh"

# --- MAIN LOGIC ---
main() {
    log_info "--- Starting Portainer API Health Check ---"

    local PORTAINER_HOSTNAME=$(get_global_config_value '.portainer_api.portainer_hostname')
    local PORTAINER_URL="https://${PORTAINER_HOSTNAME}:443/api/system/status"
    local CA_CERT_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_ca.crt"

    # 1. Check if the CA certificate exists
    if [ ! -f "$CA_CERT_PATH" ]; then
        log_error "Health check failed: Root CA certificate not found at $CA_CERT_PATH."
        return 1
    fi

    # 2. Use curl to check the endpoint
    log_info "Checking Portainer API endpoint at $PORTAINER_URL..."
    if ! curl -s --fail --cacert "$CA_CERT_PATH" "$PORTAINER_URL" > /dev/null; then
        log_error "Health check failed: Unable to connect to Portainer API at $PORTAINER_URL."
        log_error "This could be due to a firewall issue, a problem with Nginx or Traefik, or the Portainer service not being ready."
        return 1
    fi

    log_success "Portainer API is healthy and reachable."
    return 0
}

main "$@"