#!/bin/bash
#
# File: check_nginx_gateway.sh
# Description: This health check script performs a comprehensive, self-contained
#              validation of the Nginx gateway service in LXC 101.
#
# Version: 2.0.0
# Author: Roo

set -e

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Main Health Check Logic ---
main() {
    log_info "--- Starting Nginx Gateway Health Check (v2.0.0) ---"
    local NGINX_CTID="101"
    local CERT_PATH="/etc/nginx/ssl/nginx.internal.thinkheads.ai.crt"
    local KEY_PATH="/etc/nginx/ssl/nginx.internal.thinkheads.ai.key"

    # Check 1: Nginx Configuration Syntax
    log_info "Checking Nginx configuration syntax..."
    if ! pct_exec "$NGINX_CTID" -- nginx -t; then
        log_error "Nginx configuration syntax check failed in LXC ${NGINX_CTID}."
        return 1
    fi
    log_success "Nginx configuration syntax is valid."

    # Check 2: TLS Certificate and Key Validation
    log_info "Validating TLS certificate and key..."
    if ! pct_exec "$NGINX_CTID" -- test -f "$CERT_PATH"; then
        log_error "Certificate file not found at ${CERT_PATH} in LXC ${NGINX_CTID}."
        return 1
    fi
    if ! pct_exec "$NGINX_CTID" -- test -f "$KEY_PATH"; then
        log_error "Private key file not found at ${KEY_PATH} in LXC ${NGINX_CTID}."
        return 1
    fi

    local cert_modulus=$(pct_exec "$NGINX_CTID" -- openssl x509 -noout -modulus -in "$CERT_PATH")
    local key_modulus=$(pct_exec "$NGINX_CTID" -- openssl rsa -noout -modulus -in "$KEY_PATH")

    if [ "$cert_modulus" != "$key_modulus" ]; then
        log_error "Certificate and private key do not match."
        return 1
    fi
    log_success "TLS certificate and key are a valid pair."

    # Check 3: Service Status and Port Listening
    log_info "Checking service status and port listeners..."
    if ! pct_exec "$NGINX_CTID" -- systemctl is-active --quiet nginx; then
        log_error "Nginx service is not active in LXC ${NGINX_CTID}."
        return 1
    fi
    if ! pct_exec "$NGINX_CTID" -- ss -tlpn | grep -q ':80' || ! pct_exec "$NGINX_CTID" -- ss -tlpn | grep -q ':443'; then
        log_error "Nginx is not listening on required ports (80 and/or 443) in LXC ${NGINX_CTID}."
        return 1
    fi
    log_success "Nginx service is active and listening on ports 80 and 443."

    log_info "--- Nginx Gateway Health Check Passed ---"
    return 0
}

# --- Execute Main ---
main "$@"