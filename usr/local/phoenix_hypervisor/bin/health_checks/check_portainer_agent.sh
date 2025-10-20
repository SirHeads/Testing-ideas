#!/bin/bash
#
# File: check_portainer_agent.sh
# Description: This health check script verifies that the Portainer agent container
#              is running correctly in VM 1002.
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
    log_info "--- Starting Portainer Agent Health Check ---"
    local AGENT_VMID="1002"
    local CONTAINER_NAME="portainer_agent"

    # Check 1: Verify that the VM is running
    log_info "Checking if Portainer Agent VM (${AGENT_VMID}) is running..."
    if ! qm status "$AGENT_VMID" | grep -q "status: running"; then
        log_error "Portainer Agent VM ${AGENT_VMID} is not running."
        return 1
    fi
    log_success "Portainer Agent VM ${AGENT_VMID} is running."

    # Check 2: Verify that the Portainer agent container is running inside the VM
    log_info "Checking if container '${CONTAINER_NAME}' is running in VM ${AGENT_VMID}..."
    local exit_code=$(qm guest exec "$AGENT_VMID" -- /bin/bash -c "docker ps --filter 'name=${CONTAINER_NAME}' --filter 'status=running' | grep -q '${CONTAINER_NAME}'" | jq -r '.exitcode')

    if [ "$exit_code" -ne 0 ]; then
        log_error "Portainer agent container '${CONTAINER_NAME}' is not running in VM ${AGENT_VMID}."
        log_info "Debug Information:"
        log_info "  - Ensure the 'docker' feature has been successfully applied to VM ${AGENT_VMID}."
        log_info "  - Check the Docker container logs: qm guest exec ${AGENT_VMID} -- docker logs ${CONTAINER_NAME}"
        return 1
    fi
    log_success "Portainer agent container '${CONTAINER_NAME}' is running in VM ${AGENT_VMID}."

    log_info "--- Portainer Agent Health Check Passed ---"
    return 0
}

# --- Execute Main ---
main "$@"