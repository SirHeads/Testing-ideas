#!/bin/bash
#
# File: phoenix_hypervisor_feature_sync_traefik_certs.sh
# Description: This script copies the Docker client certificates to the Traefik
#              container. It is intended to be run during the 'sync' phase,
#              after the certificates have been generated.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: For logging and utility functions.
#
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../" &> /dev/null && pwd)

source "${PHOENIX_BASE_DIR}/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID="$1"

# =====================================================================================
# Function: copy_client_certs
# Description: Copies the Docker client certificates to the Traefik container.
# =====================================================================================
copy_client_certs() {
    log_info "Copying Docker client certificates to Traefik container..."
    
    local client_cert_path="/mnt/pve/quickOS/lxc-persistent-data/102/traefik/certs/client-cert.pem"
    local client_key_path="/mnt/pve/quickOS/lxc-persistent-data/102/traefik/certs/client-key.pem"
    
    # --- Verification Step ---
    if [ ! -f "$client_cert_path" ] || [ ! -f "$client_key_path" ]; then
        log_fatal "Traefik client certificate or key not found. Please run 'phoenix sync all' to generate them."
    fi

    # The CA is the same for all services, so we can copy it from the Step-CA mount
    pct exec "$CTID" -- cp /etc/step-ca/ssl/phoenix_root_ca.crt /etc/traefik/certs/ca.pem
    
    pct push "$CTID" "$client_cert_path" "/etc/traefik/certs/client-cert.pem"
    pct push "$CTID" "$client_key_path" "/etc/traefik/certs/client-key.pem"
    
    pct exec "$CTID" -- chmod 600 /etc/traefik/certs/*.pem
    
    log_success "Docker client certificates copied and permissions set."

    log_info "Restarting Traefik service to apply new certificates..."
    pct exec "$CTID" -- systemctl restart traefik
}

# =====================================================================================
# Function: main
# Description: Main entry point for the script.
# =====================================================================================
main() {
    if [ -z "$CTID" ]; then
        log_fatal "Usage: $0 <CTID>"
    fi

    log_info "Starting Traefik certificate sync for CTID $CTID."
    copy_client_certs
    log_info "Traefik certificate sync completed for CTID $CTID."
}

# --- SCRIPT EXECUTION ---
main "$@"