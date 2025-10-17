#!/bin/bash
#
# File: check_dns_resolution.sh
# Description: This health check script verifies that the internal DNS resolution
#              is working correctly by querying the dnsmasq service in LXC 101.
#
# Dependencies:
#   - dig: Must be installed on the Proxmox host.
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
    log_info "--- Starting DNS Resolution Health Check ---"

    local DNS_SERVER_IP="10.0.0.13"
    local DOMAIN_TO_CHECK=$(get_global_config_value '.portainer_api.portainer_hostname')
    local EXPECTED_INTERNAL_IP=$(get_global_config_value '.network.portainer_server_ip')
    local EXPECTED_EXTERNAL_IP=$(jq -r '.dns_server.authoritative_zones[0].records[] | select(.hostname == "portainer") | .ip_external' "$HYPERVISOR_CONFIG_FILE")

    if ! command -v dig &> /dev/null; then
        log_error "Command 'dig' not found. Please install dnsutils on the Proxmox host (apt-get install dnsutils)."
        return 1
    fi

    log_info "Querying DNS server ${DNS_SERVER_IP} for domain '${DOMAIN_TO_CHECK}'..."
    local DIG_OUTPUT
    DIG_OUTPUT=$(dig @"${DNS_SERVER_IP}" "${DOMAIN_TO_CHECK}")
    
    # Parse the resolved IP from the answer section to handle more complex outputs
    local RESOLVED_IP
    RESOLVED_IP=$(echo "$DIG_OUTPUT" | awk '/^;; ANSWER SECTION:$/{f=1;next}f==1{print $5;exit}')

    if [ -z "$RESOLVED_IP" ]; then
        log_error "DNS resolution failed. The domain '${DOMAIN_TO_CHECK}' could not be resolved by ${DNS_SERVER_IP}."
        log_info "Debug Information (Full dig output):"
        echo "$DIG_OUTPUT"
        log_info "  - Ensure LXC 101 is running and dnsmasq service is active."
        log_info "  - Check firewall rules to ensure the host can communicate with LXC 101 on port 53."
        return 1
    fi

    # In a split-horizon DNS setup, the resolved IP could be the internal or external address.
    # We need to check if the resolved IP is one of the valid addresses.
    local valid_ip_found=false
    for IP in $RESOLVED_IP; do
        if [[ "$IP" == "$EXPECTED_INTERNAL_IP" ]] || [[ "$IP" == "$EXPECTED_EXTERNAL_IP" ]]; then
            valid_ip_found=true
            log_success "DNS resolution is working correctly. '${DOMAIN_TO_CHECK}' resolved to valid IP '${IP}'."
            break
        fi
    done

    if [ "$valid_ip_found" = false ]; then
        log_error "DNS resolution returned an incorrect or unexpected IP address."
        log_info "  - Expected IPs: ${EXPECTED_INTERNAL_IP} (internal) or ${EXPECTED_EXTERNAL_IP} (external)"
        log_info "  - Resolved IPs: ${RESOLVED_IP}"
        log_info "Debug Information (Full dig output):"
        echo "$DIG_OUTPUT"
        return 1
    fi
    log_info "--- DNS Resolution Health Check Passed ---"
    return 0
}

# --- Execute Main ---
main "$@"