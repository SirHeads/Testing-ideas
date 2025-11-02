#!/bin/bash
#
# File: hypervisor_feature_bootstrap_step_cli.sh
# Description: This script idempotently bootstraps the Step CLI on the host,
#              ensuring it's configured to communicate with the Step CA server.
#
# Version: 1.0.0
# Author: Roo

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." > /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Main execution ---
log_info "--- Bootstrapping Step CLI on Hypervisor ---"

CA_URL="https://10.0.0.10:9000"
ROOT_CA_CERT_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt"

# Check if the root CA certificate exists
if [ ! -f "$ROOT_CA_CERT_PATH" ]; then
    log_fatal "Root CA certificate not found at ${ROOT_CA_CERT_PATH}. Cannot bootstrap Step CLI."
fi

# Check if the CLI is already bootstrapped to avoid unnecessary work
STEP_CONFIG_DIR="/root/.step/config"
if [ -d "$STEP_CONFIG_DIR" ] && grep -q "\"ca-url\": \"${CA_URL}\"" "${STEP_CONFIG_DIR}/defaults.json"; then
    log_info "Step CLI is already bootstrapped for ${CA_URL}. No changes needed."
else
    log_info "Bootstrapping Step CLI for CA at ${CA_URL}..."
    
    # Get the fingerprint of the root CA certificate
    FINGERPRINT=$(step certificate fingerprint "$ROOT_CA_CERT_PATH")
    if [ -z "$FINGERPRINT" ]; then
        log_fatal "Failed to get fingerprint from root CA certificate."
    fi

    # Bootstrap the Step CLI
    if ! step ca bootstrap --ca-url "$CA_URL" --fingerprint "$FINGERPRINT" --force; then
        log_fatal "Failed to bootstrap Step CLI."
    fi

    log_success "Step CLI bootstrapped successfully."
fi

log_info "--- Step CLI bootstrap process complete ---"