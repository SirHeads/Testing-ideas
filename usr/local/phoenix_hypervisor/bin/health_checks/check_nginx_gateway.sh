#!/bin/bash
#
# File: check_nginx_gateway.sh
# Description: This health check script verifies that the Nginx gateway service
#              is running correctly in LXC 101.
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
    log_info "--- Starting Nginx Gateway Health Check ---"
    local NGINX_CTID="101"

    # Check 1: Verify that the Nginx service is active
    log_info "Checking if Nginx service is active in LXC ${NGINX_CTID}..."
    if ! pct_exec "$NGINX_CTID" -- systemctl is-active --quiet nginx; then
        log_error "Nginx service is not active in LXC ${NGINX_CTID}."
        log_info "Debug Information:"
        log_info "  - Ensure LXC ${NGINX_CTID} has been created and started."
        log_info "  - Check the Nginx service status: pct exec ${NGINX_CTID} -- systemctl status nginx"
        log_info "  - Check the Nginx service logs: pct exec ${NGINX_CTID} -- journalctl -u nginx"
        return 1
    fi
    log_success "Nginx service is active in LXC ${NGINX_CTID}."

    # Check 2: Verify that Nginx is listening on ports 80 and 443
    log_info "Checking if Nginx is listening on ports 80 and 443 in LXC ${NGINX_CTID}..."
    if ! pct_exec "$NGINX_CTID" -- ss -tlpn | grep -q ':80' || ! pct_exec "$NGINX_CTID" -- ss -tlpn | grep -q ':443'; then
        log_error "Nginx is not listening on required ports (80 and/or 443) in LXC ${NGINX_CTID}."
        log_info "Debug Information:"
        log_info "  - Check the Nginx configuration for any errors: pct exec ${NGINX_CTID} -- nginx -t"
        log_info "  - Current listening ports in LXC ${NGINX_CTID}:"
        pct_exec "$NGINX_CTID" -- ss -tlpn
        return 1
    fi
    log_success "Nginx is listening on ports 80 and 443 in LXC ${NGINX_CTID}."

    log_info "--- Nginx Gateway Health Check Passed ---"
    return 0
}

# --- Execute Main ---
main "$@"