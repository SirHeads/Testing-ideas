#!/bin/bash
#
# File: check_traefik_proxy.sh
# Description: This health check script verifies that the Traefik proxy service
#              is running correctly in LXC 102.
#
# Returns:
#   0 on success, 1 on failure.
#

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Main Health Check Logic ---
main() {
    log_info "--- Starting Traefik Proxy Health Check ---"
    local TRAEFIK_CTID="102"

    # Check 1: Verify that the Traefik service is active
    log_info "Checking if Traefik service is active in LXC ${TRAEFIK_CTID}..."
    if ! pct_exec "$TRAEFIK_CTID" -- systemctl is-active --quiet traefik; then
        log_error "Traefik service is not active in LXC ${TRAEFIK_CTID}."
        log_info "Debug Information:"
        log_info "  - Ensure LXC ${TRAEFIK_CTID} has been created and started."
        log_info "  - Check the Traefik service status: pct exec ${TRAEFIK_CTID} -- systemctl status traefik"
        log_info "  - Check the Traefik service logs: pct exec ${TRAEFIK_CTID} -- journalctl -u traefik"
        return 1
    fi
    log_success "Traefik service is active in LXC ${TRAEFIK_CTID}."

    # Check 2: Verify that the Traefik /ping endpoint is responsive
    log_info "Checking if Traefik /ping endpoint is responsive in LXC ${TRAEFIK_CTID}..."
    local PING_URL="http://localhost:8080/ping"
    if ! pct_exec "$TRAEFIK_CTID" -- curl -s --fail "$PING_URL" > /dev/null; then
        log_error "Traefik /ping endpoint is not responsive."
        return 1
    fi
    log_success "Traefik /ping endpoint is responsive."

    # Check 3: Verify the TLS certificate for the dashboard
    log_info "Verifying TLS certificate for the Traefik dashboard..."
    local DASHBOARD_URL="localhost:8443"
    local EXPECTED_ISSUER="ThinkHeads Internal CA"
    
    # Use openssl s_client to get the certificate issuer
    local issuer
    issuer=$(pct_exec "$TRAEFIK_CTID" -- /bin/bash -c "echo | openssl s_client -connect ${DASHBOARD_URL} 2>/dev/null | openssl x509 -noout -issuer | sed 's/.*CN = //'")

    if [ "$issuer" != "$EXPECTED_ISSUER" ]; then
        log_error "TLS certificate issuer check failed."
        log_error "  - Expected Issuer: '${EXPECTED_ISSUER}'"
        log_error "  - Actual Issuer: '${issuer}'"
        log_info "This indicates Traefik may be using a self-signed fallback certificate instead of one from our internal CA."
        return 1
    fi
    log_success "TLS certificate for the dashboard was issued by '${EXPECTED_ISSUER}'."

    log_info "--- Traefik Proxy Health Check Passed ---"
    return 0
}

# --- Execute Main ---
main "$@"