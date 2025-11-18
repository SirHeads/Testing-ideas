#!/bin/bash
#
# File: feature_sync_docker_certs.sh
# Description: This script is responsible for ensuring that the Docker daemon
#              certificate is present and valid. It is intended to be run
#              on the hypervisor during the 'sync' phase.
#
# Version: 1.0.0
# Author: Roo

set -e

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../../" &> /dev/null && pwd)

source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- MAIN LOGIC ---
main() {
    log_info "--- Docker Certificate Sync ---"
    
    log_info "Forcing renewal of Docker daemon certificate..."
    if ! "${PHOENIX_BASE_DIR}/bin/managers/certificate-renewal-manager.sh" --force; then
        log_fatal "Failed to renew certificates."
    fi
    
    log_success "Docker certificate sync completed successfully."
}

main "$@"