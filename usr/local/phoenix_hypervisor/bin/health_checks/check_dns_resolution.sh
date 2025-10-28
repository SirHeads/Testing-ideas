#!/bin/bash
#
# File: check_dns_resolution.sh
# Description: This script performs a DNS resolution health check from either the
#              hypervisor host or a guest container.
#
# Usage:
#   ./check_dns_resolution.sh --context <host|guest> --guest-id <CTID> --domain <domain> --expected-ip <ip>
#
# Version: 1.0.0
# Author: Roo

set -e

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Argument Parsing ---
CONTEXT=""
GUEST_ID=""
DOMAIN=""
EXPECTED_IP=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --context) CONTEXT="$2"; shift ;;
        --guest-id) GUEST_ID="$2"; shift ;;
        --domain) DOMAIN="$2"; shift ;;
        --expected-ip) EXPECTED_IP="$2"; shift ;;
        *) log_error "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# --- Validation ---
if [ -z "$CONTEXT" ] || [ -z "$DOMAIN" ] || [ -z "$EXPECTED_IP" ]; then
    log_error "Usage: $0 --context <host|guest> --domain <domain> --expected-ip <ip> [--guest-id <CTID>]"
    exit 1
fi

if [ "$CONTEXT" == "guest" ] && [ -z "$GUEST_ID" ]; then
    log_error "Guest ID is required for guest context."
    exit 1
fi

# --- Main Health Check Logic ---
main() {
    log_info "--- Starting DNS Resolution Health Check ---"
    log_info "Context: $CONTEXT, Domain: $DOMAIN, Expected IP: $EXPECTED_IP"

    local resolved_ip=""
    if [ "$CONTEXT" == "host" ]; then
        resolved_ip=$(dig +short "$DOMAIN")
    elif [ "$CONTEXT" == "guest" ]; then
        resolved_ip=$(pct_exec "$GUEST_ID" -- dig +short "$DOMAIN")
    else
        log_error "Invalid context: $CONTEXT. Must be 'host' or 'guest'."
        exit 1
    fi

    if [ -z "$resolved_ip" ]; then
        log_error "DNS resolution for '$DOMAIN' failed. No IP address was returned."
        return 1
    fi

    if [ "$resolved_ip" != "$EXPECTED_IP" ]; then
        log_error "DNS resolution for '$DOMAIN' returned an incorrect IP."
        log_error "  - Expected: $EXPECTED_IP"
        log_error "  - Resolved: $resolved_ip"
        return 1
    fi

    log_success "DNS resolution for '$DOMAIN' is correct. Resolved to $resolved_ip."
    return 0
}

# --- Execute Main ---
main "$@"