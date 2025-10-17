#!/bin/bash
#
# File: check_step_ca.sh
# Description: This health check script verifies that the Step-CA service is
#              running correctly in LXC 103 and that its root certificate is
#              available on the hypervisor.
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
    log_info "--- Starting Step-CA Health Check ---"
    local STEP_CA_CTID="103"
    local ROOT_CA_CERT_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_ca.crt"

    # Check 1: Verify that the step-ca service is active
    log_info "Checking if step-ca service is active in LXC ${STEP_CA_CTID}..."
    if ! pct_exec "$STEP_CA_CTID" -- systemctl is-active --quiet step-ca; then
        log_error "Step-CA service is not active in LXC ${STEP_CA_CTID}."
        log_info "Debug Information:"
        log_info "  - Ensure LXC ${STEP_CA_CTID} has been created and started."
        log_info "  - Check the Step-CA service status: pct exec ${STEP_CA_CTID} -- systemctl status step-ca"
        log_info "  - Check the Step-CA service logs: pct exec ${STEP_CA_CTID} -- journalctl -u step-ca"
        return 1
    fi
    log_success "Step-CA service is active in LXC ${STEP_CA_CTID}."

    # Check 2: Verify that the root CA certificate exists on the hypervisor
    log_info "Checking for root CA certificate at ${ROOT_CA_CERT_PATH}..."
    if [ ! -f "$ROOT_CA_CERT_PATH" ]; then
        log_error "Root CA certificate not found at ${ROOT_CA_CERT_PATH}."
        log_info "Debug Information:"
        log_info "  - The certificate should be exported by the lxc-manager.sh script after CTID 103 is created."
        log_info "  - Check the logs for the creation of CTID 103 for any errors."
        return 1
    fi
    log_success "Root CA certificate found at ${ROOT_CA_CERT_PATH}."

    log_info "--- Step-CA Health Check Passed ---"
    return 0
}

# --- Execute Main ---
main "$@"