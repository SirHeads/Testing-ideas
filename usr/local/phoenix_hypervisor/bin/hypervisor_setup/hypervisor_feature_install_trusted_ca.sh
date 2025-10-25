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
    local source_ca_path_on_host="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt"
    local host_ca_destination_path="/usr/local/share/ca-certificates/phoenix_internal_root_ca.crt"

    # Check if the source CA certificate exists on the host
    if [ ! -f "$source_ca_path_on_host" ]; then
        log_fatal "Source Root CA certificate not found at ${source_ca_path_on_host}. Cannot install host trusted CA."
    fi

    log_info "Copying Root CA from ${source_ca_path_on_host} to ${host_ca_destination_path}..."
    if ! cp "$source_ca_path_on_host" "$host_ca_destination_path"; then
        log_fatal "Failed to copy Root CA certificate to host's trust store."
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