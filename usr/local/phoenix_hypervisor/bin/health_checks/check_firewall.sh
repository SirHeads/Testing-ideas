#!/bin/bash
#
# File: check_firewall.sh
# Description: This health check script verifies that the Proxmox firewall is
#              active and that essential rules are correctly configured.
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
    log_info "--- Starting Firewall Health Check ---"
    local FIREWALL_CONFIG="/etc/pve/firewall/cluster.fw"

    # Check 1: Verify that the pve-firewall service is running
    log_info "Checking if pve-firewall service is active..."
    if ! systemctl is-active --quiet pve-firewall; then
        log_error "pve-firewall service is not active."
        log_info "Debug Information:"
        log_info "  - Check the service status: systemctl status pve-firewall"
        log_info "  - Ensure the firewall is enabled in the Proxmox datacenter settings."
        return 1
    fi
    log_success "pve-firewall service is active."

    # Check 2: Verify that the cluster firewall configuration file exists
    log_info "Checking for firewall configuration file at ${FIREWALL_CONFIG}..."
    if [ ! -f "$FIREWALL_CONFIG" ]; then
        log_error "Firewall configuration file not found at ${FIREWALL_CONFIG}."
        log_info "Debug Information:"
        log_info "  - This file should be created by the 'phoenix setup' command."
        log_info "  - Check the logs for the hypervisor setup for any errors."
        return 1
    fi
    log_success "Firewall configuration file found."

    # Check 3: Verify a key rule (e.g., allow HTTPS to Nginx gateway)
    log_info "Verifying essential firewall rules..."
    local RULE_TO_CHECK="IN ACCEPT -p tcp -dport 443"
    if ! grep -q "${RULE_TO_CHECK}" "$FIREWALL_CONFIG"; then
        log_error "Essential firewall rule '${RULE_TO_CHECK}' is missing from ${FIREWALL_CONFIG}."
        log_info "Debug Information:"
        log_info "  - The firewall rules are generated based on the 'phoenix_hypervisor_config.json' file."
        log_info "  - Ensure the 'phoenix setup' command has been run successfully."
        return 1
    fi
    log_success "Essential firewall rule '${RULE_TO_CHECK}' is present."

    log_info "--- Firewall Health Check Passed ---"
    return 0
}

# --- Execute Main ---
main "$@"