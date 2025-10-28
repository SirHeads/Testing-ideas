#!/bin/bash
#
# File: run-step-ca.sh
# Description: This script initializes and runs the Step CA service. It is
#              designed to be idempotent, ensuring that initialization
#              only occurs once.
#

set -e

# --- Script Variables ---
STEP_CA_DIR="/etc/step-ca"
SSL_DIR="${STEP_CA_DIR}/ssl"
CONFIG_DIR="${STEP_CA_DIR}/config"
INIT_LOCK_FILE="${STEP_CA_DIR}/.initialized"

# --- Logging ---
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_fatal() {
    echo "[FATAL] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    exit 1
}

# --- Initialization Function ---
initialize_ca() {
    log_info "Step CA not initialized. Starting initialization..."

    # Ensure the SSL directory exists and has the correct permissions
    mkdir -p "${SSL_DIR}"

    # Get required values from hypervisor config (assuming it's mounted or copied)
    # This is a placeholder for the actual mechanism to get these values
    local root_ca_name="ThinkHeads Internal CA"
    local intermediate_ca_name="ThinkHeads Internal CA Intermediate CA"
    local dns_name="ca.internal.thinkheads.ai"
    local address=":9000"
    local provisioner_name="admin@thinkheads.ai"
    
    # Generate a random password for the provisioner
    openssl rand -base64 32 > "${SSL_DIR}/provisioner_password.txt"

    # Initialize the CA
    step ca init --name "$root_ca_name" --provisioner "$provisioner_name" \
        --dns "$dns_name" --dns "phoenix.thinkheads.ai" --dns "*.phoenix.thinkheads.ai" --dns "*.internal.thinkheads.ai" \
        --address "$address" --password-file "${SSL_DIR}/ca_password.txt" --provisioner-password-file "${SSL_DIR}/provisioner_password.txt" \
        --with-ca-url "https://${dns_name}:9000"

    # Add ACME provisioner
    step ca provisioner add acme --type ACME

    # Export the root certificate and fingerprint
    step certificate fingerprint "${CONFIG_DIR}/root_ca.crt" > "${SSL_DIR}/root_ca.fingerprint"
    cp "${CONFIG_DIR}/root_ca.crt" "${SSL_DIR}/phoenix_root_ca.crt"
    cat "${CONFIG_DIR}/intermediate_ca.crt" "${CONFIG_DIR}/root_ca.crt" > "${SSL_DIR}/phoenix_ca.crt"

    # Create the lock file
    touch "${INIT_LOCK_FILE}"
    log_info "Step CA initialization complete."
}

# --- Main Execution ---
if [ ! -f "${INIT_LOCK_FILE}" ]; then
    initialize_ca
fi

log_info "Starting Step CA service..."
step-ca "${CONFIG_DIR}/ca.json" --password-file "${SSL_DIR}/ca_password.txt"