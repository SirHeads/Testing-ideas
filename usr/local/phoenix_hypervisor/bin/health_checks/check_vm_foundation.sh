#!/bin/bash
#
# File: check_vm_foundation.sh
# Description: This script performs a comprehensive health check on the foundational
#              configuration of any given VM. It validates prerequisites, DNS,
#              network connectivity, firewall rules, certificate trust, and the
#              Docker service.
#
# Version: 1.0.0
# Author: Roo

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
VMID="$1" # The VMID is now passed as an argument

# =====================================================================================
# Function: main
# Description: Main entry point for the script.
# =====================================================================================
main() {
    if [ -z "$VMID" ]; then
        log_fatal "Usage: $0 <VMID>"
    fi

    log_info "--- Starting Foundational Health Check for VM ${VMID} ---"

    check_prerequisites || exit 1
    check_dns_resolution || exit 1
    check_firewall || exit 1
    check_certificate_trust || exit 1
    check_docker_service || exit 1

    log_success "--- Foundational Health Check for VM ${VMID} Completed Successfully ---"
}

# =====================================================================================
# Function: check_prerequisites
# Description: Checks for required commands and running LXC containers.
# =====================================================================================
check_prerequisites() {
    log_info "Phase 1: Checking prerequisites..."
    local required_commands=("jq" "curl" "pct" "qm")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" > /dev/null; then
            log_error "Required command '$cmd' not found. Please install it."
            return 1
        fi
    done
    log_info "  - All required commands are present."

    local required_lxcs=("101" "102" "103")
    for lxc_id in "${required_lxcs[@]}"; do
        if ! pct status "$lxc_id" | grep -q "running"; then
            log_error "Required LXC container ${lxc_id} is not running."
            return 1
        fi
    done
    log_info "  - All required LXC containers (101, 102, 103) are running."

    if ! qm status "$VMID" | grep -q "running"; then
        log_error "VM ${VMID} is not running."
        return 1
    fi
    log_info "  - VM ${VMID} is running."

    log_success "Phase 1: Prerequisites check passed."
    return 0
}

# =====================================================================================
# Function: check_dns_resolution
# Description: Checks DNS resolution from the hypervisor and within the guest VM.
# =====================================================================================
check_dns_resolution() {
    log_info "Phase 2: Checking DNS resolution..."
    local vm_config
    vm_config=$(jq_get_vm_value "$VMID" ".")
    local target_host
    local service_name
    service_name=$(echo "$vm_config" | jq -r '.name' | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')
    local public_hostname="${service_name}.internal.thinkheads.ai"
    local nginx_gateway_ip="10.0.0.153"
    local traefik_mesh_ip="10.0.0.12"

    # --- Check 1: Hypervisor to Gateway (Simulates External User) ---
    log_info "  - Checking DNS resolution for ${public_hostname} from hypervisor..."
    local hypervisor_resolved_ip
    hypervisor_resolved_ip=$(getent hosts "$public_hostname" | awk '{print $1}')
    if [ "$hypervisor_resolved_ip" != "$traefik_mesh_ip" ]; then
        log_error "DNS resolution failed on hypervisor. Expected '$traefik_mesh_ip' (Traefik Mesh) for '$public_hostname', but got '$hypervisor_resolved_ip'."
        return 1
    fi
    log_info "    - Hypervisor correctly resolved '$public_hostname' to the Traefik Mesh IP '$traefik_mesh_ip'."

    # --- Check 2: Guest VM to Service Mesh (Internal Communication) ---
    log_info "  - Checking DNS resolution for ${public_hostname} from within VM ${VMID}..."
    local vm_resolved_ip
    vm_resolved_ip=$(qm guest exec "$VMID" -- getent hosts "$public_hostname" | jq -r '."out-data"' | awk '{print $1}')
    if [ "$vm_resolved_ip" != "$traefik_mesh_ip" ]; then
        log_error "DNS resolution failed inside VM ${VMID}. Expected '$traefik_mesh_ip' (Traefik Mesh) for '$public_hostname', but got '$vm_resolved_ip'."
        return 1
    fi
    log_info "    - VM ${VMID} correctly resolved '$public_hostname' to the Traefik Mesh IP '$traefik_mesh_ip'."

    log_success "Phase 2: DNS resolution check passed."
    return 0
}

# =====================================================================================
# Function: check_firewall
# Description: Checks if the firewall is enabled for the VM.
# =====================================================================================
check_firewall() {
    log_info "Phase 3: Checking firewall status..."
    if ! qm config "$VMID" | grep -q "firewall=1"; then
        log_error "Firewall is not enabled on the network interface for VM ${VMID}."
        return 1
    fi
    log_info "  - Firewall is correctly enabled on the VM's network interface."
    log_success "Phase 3: Firewall check passed."
    return 0
}

# =====================================================================================
# Function: check_certificate_trust
# Description: Validates the end-to-end certificate trust chain by making a TLS request
#              from the guest VM to an internal service (Traefik dashboard).
# =====================================================================================
check_certificate_trust() {
    log_info "Phase 4: Performing real-world certificate trust check..."
    local traefik_hostname="traefik.phoenix.thinkheads.ai"
    local traefik_ping_url="https://${traefik_hostname}/ping"

    log_info "  - Attempting to connect from VM ${VMID} to ${traefik_ping_url}..."

    # This command implicitly tests DNS, network connectivity, and certificate trust.
    # The guest's default CA trust store is used, which should include our custom CA.
    local curl_command="curl --fail --silent --show-error ${traefik_ping_url}"

    local output
    local exit_code=0
    output=$(qm guest exec "$VMID" -- /bin/bash -c "$curl_command" 2>&1) || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        local guest_exitcode
        guest_exitcode=$(echo "$output" | jq -r '.exitcode // "0"')
        if [ "$guest_exitcode" -ne 0 ]; then
            log_error "Real-world TLS connection test failed with guest exit code: $guest_exitcode"
            log_error "  - This indicates a problem with DNS, firewall rules, or the CA trust store in VM ${VMID}."
            log_error "  - To debug, SSH into the VM and run: ${curl_command} -v"
            log_error "  - Raw output: $(echo "$output" | jq -r '."err-data" // ""')"
            return 1
        fi
    fi

    log_info "  - Successfully connected to the internal service with a valid TLS certificate."
    log_success "Phase 4: Certificate trust check passed."
    return 0
}

# =====================================================================================
# Function: check_docker_service
# Description: Checks if the Docker service is running and responsive inside the VM.
# =====================================================================================
check_docker_service() {
    log_info "Phase 5: Checking Docker service status..."
    log_info "  - Executing 'docker info' inside VM ${VMID}..."

    # The command will be executed via qm guest exec. We check the exit code.
    if ! qm guest exec "$VMID" -- docker info > /dev/null 2>&1; then
        log_error "The Docker daemon inside VM ${VMID} is not running or is unresponsive."
        log_error "  - SSH into the VM and check the status with 'systemctl status docker' and 'journalctl -u docker'."
        return 1
    fi

    log_info "  - Docker daemon is running and responsive."
    log_success "Phase 5: Docker service check passed."
    return 0
}


# --- SCRIPT EXECUTION ---
main "$@"