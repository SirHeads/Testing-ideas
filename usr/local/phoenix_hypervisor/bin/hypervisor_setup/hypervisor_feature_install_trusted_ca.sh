#!/bin/bash
#
# File: hypervisor_feature_install_trusted_ca.sh
# Description: This script installs the internal root CA certificate into the
#              Proxmox host's system-wide trust store. This is essential for
#              any host-level tools (like curl) that need to communicate with
#              internal, TLS-secured services.
#
# Version: 1.0.0
# Author: Roo

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# =====================================================================================
# Function: install_host_trusted_ca
# Description: Pulls the root CA certificate from the Step-CA container and
#              installs it on the Proxmox host.
# =====================================================================================
install_host_trusted_ca() {
    log_info "--- Installing internal Root CA certificate on the Proxmox host ---"

    local step_ca_ctid="103"
    local source_ca_path_in_container="/root/.step/certs/root_ca.crt"
    local host_ca_destination_path="/usr/local/share/ca-certificates/phoenix_internal_root_ca.crt"

    # Check if the Step-CA container is running
    if ! pct status "$step_ca_ctid" > /dev/null 2>&1; then
        log_warn "Step-CA container (${step_ca_ctid}) is not running. Cannot install host trusted CA."
        return 1
    fi

    log_info "Pulling Root CA from LXC ${step_ca_ctid} to ${host_ca_destination_path}..."
    if ! pct pull "$step_ca_ctid" "$source_ca_path_in_container" "$host_ca_destination_path"; then
        log_fatal "Failed to pull Root CA certificate from Step-CA container."
    fi

    log_info "Forcing reconfiguration of ca-certificates to ensure new CA is recognized..."
    if ! dpkg-reconfigure -f noninteractive ca-certificates; then
        log_fatal "Failed to reconfigure ca-certificates package."
    fi

    log_info "Updating the host's certificate trust store..."
    if ! update-ca-certificates; then
        log_fatal "Failed to update the host's certificate trust store after reconfiguration."
    fi

    log_success "Internal Root CA certificate successfully installed on the Proxmox host."
}

# --- Main execution ---
install_host_trusted_ca