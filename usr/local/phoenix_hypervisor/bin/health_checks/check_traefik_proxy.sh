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
    local PING_ATTEMPTS=3
    local PING_DELAY=2

    for ((i=1; i<=PING_ATTEMPTS; i++)); do
        if pct_exec "$TRAEFIK_CTID" -- curl -s --fail "$PING_URL" > /dev/null; then
            log_success "Traefik /ping endpoint is responsive in LXC ${TRAEFIK_CTID}."
            log_info "--- Traefik Proxy Health Check Passed ---"
            return 0
        fi
        if [ "$i" -lt "$PING_ATTEMPTS" ]; then
            log_info "Traefik /ping endpoint not yet responsive. Retrying in ${PING_DELAY} seconds..."
            sleep "$PING_DELAY"
        fi
    done

    log_error "Traefik /ping endpoint is not responsive in LXC ${TRAEFIK_CTID} after ${PING_ATTEMPTS} attempts."
    log_info "Debug Information:"
    log_info "  - Check the Traefik logs for any API-related errors: pct exec ${TRAEFIK_CTID} -- journalctl -u traefik"
    log_info "  - Ensure the Traefik API is enabled in the configuration to expose the /ping endpoint."
    return 1

    log_info "--- Traefik Proxy Health Check Passed ---"
    return 0
}

# --- Execute Main ---
main "$@"