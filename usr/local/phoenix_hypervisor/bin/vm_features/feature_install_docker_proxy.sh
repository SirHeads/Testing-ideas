#!/bin/bash
#
# File: feature_install_docker_proxy.sh
# Description: This script configures the Docker daemon for secure TLS access and
#              sets up a Docker client context to ensure local commands also use TLS.
#
# Version: 7.0.0
# Author: Roo

set -e

# --- SCRIPT INITIALIZATION ---
source "/mnt/persistent/.phoenix_scripts/phoenix_hypervisor_common_utils.sh"

# --- MAIN LOGIC ---
main() {
    log_info "--- Configuring Docker Client for Secure TLS Access ---"

    # Define certificate paths inside the VM (these are placed by the post-renewal command)
    local CA_CERT_PATH="/etc/docker/tls/ca.pem"
    local CLIENT_CERT_PATH="/etc/docker/tls/cert.pem"
    local CLIENT_KEY_PATH="/etc/docker/tls/key.pem"

    # --- Create Docker Client Context ---
    log_info "Ensuring Docker client context 'phoenix' is up-to-date for secure TLS communication..."
    
    local DOCKER_HOST_SETTINGS="host=tcp://127.0.0.1:2376,ca=${CA_CERT_PATH},cert=${CLIENT_CERT_PATH},key=${CLIENT_KEY_PATH}"

    # Check if the context already exists
    if docker context inspect phoenix >/dev/null 2>&1; then
        log_info "Context 'phoenix' already exists. Updating it with the latest certificate paths..."
        docker context update phoenix --docker "${DOCKER_HOST_SETTINGS}"
    else
        log_info "Context 'phoenix' not found. Creating it now..."
        docker context create phoenix --docker "${DOCKER_HOST_SETTINGS}"
    fi
    
    log_info "Setting 'phoenix' as the default Docker context..."
    docker context use phoenix

    log_success "Docker client context 'phoenix' created and set as default."
}

main "$@"