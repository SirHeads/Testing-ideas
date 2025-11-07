#!/bin/bash
#
# File: feature_install_trusted_ca.sh
# Description: This feature script installs the Phoenix Hypervisor's root CA certificate
#              into the trusted store of a VM. This allows the VM to trust internal
#              services that use SSL certificates issued by the Step-CA.
#
# Arguments:
#   $1 - The VMID of the VM.
#
# Dependencies:
#   - The root CA certificate must be available in the VM's persistent storage.
#
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

set -e

# --- SCRIPT INITIALIZATION ---
# This script runs inside the VM, so paths are relative to the VM's filesystem.
LOG_FILE="/var/log/phoenix_feature_trusted_ca.log"
exec &> >(tee -a "$LOG_FILE")

# Determine the absolute path of the script's directory to ensure reliable sourcing.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
VMID="$1"
# The CA files are staged on the persistent mount, which is standardized to /mnt/persistent
CA_CERT_SOURCE_PATH="/tmp/phoenix_root_ca.crt"
CA_CERT_DEST_PATH="/usr/local/share/ca-certificates/phoenix_root_ca.crt"

# =====================================================================================
# Function: main
# Description: Main entry point for the script.
# Arguments:
#   $1 - The VMID of the VM.
# Returns:
#   None.
# =====================================================================================
main() {
    if [ -z "$VMID" ]; then
        log_fatal "Usage: $0 <VMID>"
    fi

    log_info "--- Starting trusted CA installation for VMID $VMID ---"

    # 1. Verify the source CA certificate exists
    if [ ! -f "$CA_CERT_SOURCE_PATH" ]; then
        log_fatal "Root CA certificate not found at $CA_CERT_SOURCE_PATH inside the VM. Cannot proceed."
    fi

    # 2. Copy the root CA certificate to the system's trust store
    log_info "Copying root CA certificate to $CA_CERT_DEST_PATH..."
    if ! cp "$CA_CERT_SOURCE_PATH" "$CA_CERT_DEST_PATH"; then
        log_fatal "Failed to copy root CA certificate to trust store."
    fi

    # 3. Update the certificate store
    log_info "Updating certificate store..."
    if ! update-ca-certificates; then
        log_fatal "Failed to update certificate store."
    fi

    # 4. Securely remove the temporary CA certificate
    # The source file is now on a persistent NFS mount, so we no longer remove it.
    log_info "CA certificate has been installed."

    # 5. Restart Docker to apply the new trust settings
    log_info "Restarting Docker daemon to apply new CA certificate..."
    if ! systemctl restart docker; then
        log_warn "Failed to restart Docker daemon. This might cause issues with trust."
    fi

    log_info "--- Trusted CA installation completed for VMID $VMID ---"
}

# --- SCRIPT EXECUTION ---
main "$@"