#!/bin/bash
#
# File: run-step-ca.sh
# Description: This script runs the Step CA service. It is designed to be
#              called by the systemd service and relies on the CA having
#              already been initialized by the phoenix_hypervisor_lxc_103.sh
#              script.

set -e

# --- Centralized State Variables ---
# This script now fully respects the centralized state directory established
# by the main LXC 103 setup script.
export STEPPATH="/etc/step-ca/ssl"
CA_CONFIG_FILE="${STEPPATH}/config/ca.json"
CA_PASSWORD_FILE="${STEPPATH}/ca_password.txt"

# --- Logging ---
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_fatal() {
    echo "[FATAL] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    exit 1
}

# --- Main Execution ---
# The initialization logic has been removed. This script's only responsibility
# is to run the CA service. The phoenix_hypervisor_lxc_103.sh script is the
# single source of truth for initialization.

if [ ! -f "$CA_CONFIG_FILE" ]; then
    log_fatal "Step CA config file not found at ${CA_CONFIG_FILE}. The CA must be initialized first."
fi

if [ ! -f "$CA_PASSWORD_FILE" ]; then
    log_fatal "Step CA password file not found at ${CA_PASSWORD_FILE}. The CA must be initialized first."
fi

log_info "Starting Step CA service with config: ${CA_CONFIG_FILE}"
step-ca "${CA_CONFIG_FILE}" --password-file "${CA_PASSWORD_FILE}"