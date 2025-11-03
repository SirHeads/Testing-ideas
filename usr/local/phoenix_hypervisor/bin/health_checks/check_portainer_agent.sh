#!/bin/bash
#
# File: check_portainer_agent.sh
# Description: This health check script verifies that a Portainer agent is running
#              and network-accessible.
#
# Usage: ./check_portainer_agent.sh <VMID>
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
    local AGENT_VMID="$1"

    if [ -z "$AGENT_VMID" ]; then
        log_error "Usage: $0 <VMID>"
        return 1
    fi

    # Check 1: Verify that the VM is running
    log_info "Checking if Portainer Agent VM (${AGENT_VMID}) is running..."
    if ! qm status "$AGENT_VMID" | grep -q "status: running"; then
        log_error "Portainer Agent VM ${AGENT_VMID} is not running."
        return 1
    fi
    log_success "Portainer Agent VM ${AGENT_VMID} is running."

    # Check 2: Get Agent IP and Port from config
    log_info "Retrieving agent network configuration for VM ${AGENT_VMID}..."
    local AGENT_IP=$(jq -r ".vms[] | select(.vmid == ${AGENT_VMID}) | .network_config.ip" "$VM_CONFIG_FILE" | cut -d'/' -f1)
    local AGENT_PORT=$(get_global_config_value '.network.portainer_agent_port')

    if [ -z "$AGENT_IP" ] || [ "$AGENT_IP" == "null" ]; then
        log_error "Could not determine IP address for VM ${AGENT_VMID} from configuration."
        return 1
    fi
    log_info "Agent is expected at: ${AGENT_IP}:${AGENT_PORT}"

    # Check 3: Perform a network-level health check from the hypervisor
    log_info "Pinging agent's /ping endpoint from the hypervisor..."
    local PING_URL="https://{AGENT_IP}:${AGENT_PORT}/ping"
    
    # We use --insecure because the certificate is for the agent's hostname, not its IP address.
    # This check is purely for network reachability and service health.
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" --insecure "https://${AGENT_IP}:${AGENT_PORT}/ping")

    if [ "$http_status" -ne 204 ]; then
        log_error "Portainer agent on VM ${AGENT_VMID} is not healthy or reachable from the hypervisor."
        log_error "  - Endpoint URL: https://${AGENT_IP}:${AGENT_PORT}/ping"
        log_error "  - Received HTTP Status: ${http_status} (Expected: 204)"
        log_info "Debug Information:"
        log_info "  - Verify the 'docker' feature installed correctly on VM ${AGENT_VMID}."
        log_info "  - Check the Portainer agent container logs: qm guest exec ${AGENT_VMID} -- docker logs portainer_agent"
        log_info "  - Check firewall rules on the hypervisor and within the VM."
        return 1
    fi
    log_success "Portainer agent is running and network-accessible."

    log_info "--- Portainer Agent Health Check Passed ---"
    return 0
}

# --- Execute Main ---
main "$@"