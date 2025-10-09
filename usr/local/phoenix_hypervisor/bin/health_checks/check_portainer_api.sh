#!/bin/bash
#
# File: check_portainer_api.sh
# Description: Robust health check script to verify Portainer API responsiveness.
#              It polls the /api/status endpoint and returns 0 on success, 1 on failure.
#              Includes enhanced logging and error handling.
#
# Arguments:
#   $1 - Portainer Hostname (e.g., portainer.phoenix.local)
#   $2 - Portainer HTTPS port (e.g., 9443)
#   $3 - Path to the CA certificate file (e.g., /persistent-storage/ssl/portainer.phoenix.local.crt)
#
# Returns:
#   0 if Portainer API is responsive, 1 otherwise.
#
 
set -euo pipefail # Exit immediately if a command exits with a non-zero status, exit if an unset variable is used, and propagate errors through pipes.
 
# Source common utilities
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR="/usr/local/phoenix_hypervisor" # Fixed base directory for hypervisor scripts
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"
 
# --- Argument Parsing and Validation ---
PORTAINER_HOSTNAME="${1:-}"
PORTAINER_PORT="${2:-}"
CA_CERT_PATH="${3:-}"
 
if [[ -z "$PORTAINER_HOSTNAME" || -z "$PORTAINER_PORT" || -z "$CA_CERT_PATH" ]]; then
    log_error "Usage: $0 <portainer_hostname> <portainer_port> <ca_cert_path>"
    return 1
fi
 
PORTAINER_URL="https://${PORTAINER_HOSTNAME}:${PORTAINER_PORT}/api/status"
MAX_ATTEMPTS=60 # Increased attempts for robustness
INTERVAL=5      # Reduced interval for faster checks
ATTEMPTS=0
 
log_info "Starting Portainer API health check."
log_info "Target URL: ${PORTAINER_URL}"
log_info "CA Certificate Path: ${CA_CERT_PATH}"
log_info "Max attempts: ${MAX_ATTEMPTS}, Interval: ${INTERVAL} seconds."
 
# --- Pre-check: Ensure certificate file exists ---
if [[ ! -f "$CA_CERT_PATH" ]]; then
    log_error "CA certificate file not found at: ${CA_CERT_PATH}. Please ensure it exists and is accessible."
    return 1
fi
 
# --- Health Check Loop ---
while [[ "$ATTEMPTS" -lt "$MAX_ATTEMPTS" ]]; do
    ATTEMPTS=$((ATTEMPTS + 1))
    log_info "Attempt ${ATTEMPTS}/${MAX_ATTEMPTS}: Checking Portainer API responsiveness..."
 
    # Use curl with increased verbosity for debugging, but suppress actual output unless it fails
    # --insecure is removed as we expect the certificate to be valid now
    if curl --silent --fail --show-error --cacert "$CA_CERT_PATH" "$PORTAINER_URL" > /dev/null; then
        log_success "Portainer API is responsive after ${ATTEMPTS} attempts."
        exit 0
    else
        curl_exit_code=$?
        log_warn "Portainer API not yet responsive (curl exit code: ${curl_exit_code}). Retrying in ${INTERVAL} seconds..."
        sleep "$INTERVAL"
    fi
done
 
log_error "Portainer API did not become responsive after ${MAX_ATTEMPTS} attempts. Health check failed."
return 1