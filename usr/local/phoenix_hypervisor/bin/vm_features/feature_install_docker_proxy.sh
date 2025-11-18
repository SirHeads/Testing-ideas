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
    log_info "--- Configuring Docker Daemon and Client for Secure TLS Access ---"

    local DOCKER_CONFIG_DIR="/etc/docker"
    local DAEMON_JSON_FILE="${DOCKER_CONFIG_DIR}/daemon.json"
    local CERT_DIR="${DOCKER_CONFIG_DIR}/certs"

    # Define certificate paths inside the VM
    local CA_CERT_PATH="${CERT_DIR}/ca.pem"
    local SERVER_CERT_PATH="${CERT_DIR}/server-cert.pem"
    local SERVER_KEY_PATH="${CERT_DIR}/server-key.pem"

    # Create the Docker config and certs directories
    mkdir -p "$CERT_DIR"

    # --- Certificate Placement ---
    local shared_cert_path="/mnt/persistent/docker/certs"
    cp "${shared_cert_path}/server-cert.pem" "$SERVER_CERT_PATH"
    cp "${shared_cert_path}/server-key.pem" "$SERVER_KEY_PATH"
    cp "/tmp/phoenix_root_ca.crt" "$CA_CERT_PATH"

    # --- Create daemon.json ---
    log_info "Creating Docker daemon configuration at ${DAEMON_JSON_FILE}..."
    jq -n \
      --argjson tlsverify true \
      --arg tlscacert "$CA_CERT_PATH" \
      --arg tlscert "$SERVER_CERT_PATH" \
      --arg tlskey "$SERVER_KEY_PATH" \
      --argjson hosts '["tcp://0.0.0.0:2376"]' \
      '{
        "tlsverify": $tlsverify,
        "tlscacert": $tlscacert,
        "tlscert": $tlscert,
        "tlskey": $tlskey,
        "hosts": $hosts
      }' > "$DAEMON_JSON_FILE"

    log_success "Docker daemon.json created successfully."

    # --- Restart Docker Service ---
    log_info "Restarting Docker service to apply new configuration..."
    if ! systemctl restart docker; then
        log_fatal "Failed to restart Docker service. Please check the logs."
    fi
    log_success "Docker service restarted successfully."

    # --- Create Docker Client Context ---
    log_info "Creating Docker client context 'phoenix' for secure TLS communication..."
    docker context create phoenix \
      --docker "host=tcp://127.0.0.1:2376,ca=${CA_CERT_PATH},cert=${SERVER_CERT_PATH},key=${SERVER_KEY_PATH}"
    
    log_info "Setting 'phoenix' as the default Docker context..."
    docker context use phoenix

    log_success "Docker client context 'phoenix' created and set as default."
}

main "$@"