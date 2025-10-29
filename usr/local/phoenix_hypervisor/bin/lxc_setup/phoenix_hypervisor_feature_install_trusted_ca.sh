#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_trusted_ca.sh
# Description: This feature script installs the Phoenix Hypervisor's root CA certificate
#              into the trusted store of an LXC container. This allows the container to
#              trust internal services that use SSL certificates issued by the Step-CA.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Dependencies:
#   - The root CA certificate must be available at the specified location on the hypervisor.
#
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

set -e

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID="$1"
CA_CERT_SOURCE_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt"
CA_CERT_DEST_PATH="/usr/local/share/ca-certificates/phoenix_root_ca.crt"

# =====================================================================================
# Function: main
# Description: Main entry point for the script.
# Arguments:
#   $1 - The CTID of the container.
# Returns:
#   None.
# =====================================================================================
main() {
    if [ "$#" -lt 1 ]; then
        log_fatal "Usage: $0 <CTID>"
        log_fatal "This script requires at least the LXC Container ID as an argument."
        exit 1
    fi

    log_info "Starting trusted CA installation for CTID $CTID."

    # 1. Clean up any previous installations to ensure a clean state
    log_info "Cleaning up any stale Phoenix CA certificates..."
    pct exec "$CTID" -- find /usr/local/share/ca-certificates/ -name 'phoenix_*.crt' -delete || log_warn "Could not clean up old certificates. This may be a fresh installation."

    # 2. Copy the root CA certificate from the hypervisor to the container
    log_info "Copying root CA certificate from mounted path to trust store..."
    if ! pct push "$CTID" "$CA_CERT_SOURCE_PATH" "$CA_CERT_DEST_PATH"; then
        log_fatal "Failed to copy root CA certificate to container $CTID."
    fi

    # 2. Update the certificate store in the container
    log_info "Updating certificate store in container..."
    if ! pct exec "$CTID" -- update-ca-certificates; then
        log_fatal "Failed to update certificate store in container $CTID."
    fi

    log_info "Trusted CA installation completed for CTID $CTID."
}

# --- SCRIPT EXECUTION ---
main "$@"