#!/bin/bash
#
# File: check_portainer_server.sh
# Description: This health check script verifies that the Portainer server container
#              is running correctly in VM 1001.
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
    log_info "--- Starting Portainer Server Health Check ---"
    local PORTAINER_VMID="1001"
    local CONTAINER_NAME="portainer_server"

    # Check 1: Verify that the VM is running
    log_info "Checking if Portainer VM (${PORTAINER_VMID}) is running..."
    if ! qm status "$PORTAINER_VMID" | grep -q "status: running"; then
        log_error "Portainer VM ${PORTAINER_VMID} is not running."
        return 1
    fi
    log_success "Portainer VM ${PORTAINER_VMID} is running."

    # Check 2: Verify that the Portainer server container is running inside the VM
    log_info "Checking if container '${CONTAINER_NAME}' is running in VM ${PORTAINER_VMID}..."
    local exit_code=$(qm guest exec "$PORTAINER_VMID" -- /bin/bash -c "docker ps --filter 'name=${CONTAINER_NAME}' --filter 'status=running' | grep -q '${CONTAINER_NAME}'" | jq -r '.exitcode')

    if [ "$exit_code" -ne 0 ]; then
        log_error "Portainer server container '${CONTAINER_NAME}' is not running in VM ${PORTAINER_VMID}."
        log_info "Debug Information:"
        log_info "  - Ensure the 'docker' feature has been successfully applied to VM ${PORTAINER_VMID}."
        log_info "  - Check the Docker container logs: qm guest exec ${PORTAINER_VMID} -- docker logs ${CONTAINER_NAME}"
        return 1
    fi
    log_success "Portainer server container '${CONTAINER_NAME}' is running in VM ${PORTAINER_VMID}."

    log_info "--- Portainer Server Health Check Passed ---"
    return 0
}

# --- Execute Main ---
main "$@"