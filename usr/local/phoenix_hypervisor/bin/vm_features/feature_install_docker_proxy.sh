#!/bin/bash
#
# File: feature_install_docker_proxy.sh
# Description: This feature script installs and configures a secure Docker socket proxy
#              inside a VM. It assumes that the necessary TLS certificates have already
#              been placed in /etc/docker/certs.d by the vm-manager.
#
# Version: 2.0.0
# Author: Roo
#

# --- SCRIPT INITIALIZATION ---
# This script runs inside the VM, so paths are relative to the VM's filesystem.
source "/persistent-storage/.phoenix_scripts/phoenix_hypervisor_common_utils.sh"

# --- MAIN LOGIC ---
main() {
    local VMID="$1"
    log_info "--- Starting Docker Socket Proxy Installation for VMID: ${VMID} ---"

    # --- CONFIGURATION (from within the VM) ---
    export HYPERVISOR_CONFIG_FILE="/persistent-storage/.phoenix_scripts/phoenix_hypervisor_config.json"
    export VM_CONFIG_FILE="/persistent-storage/.phoenix_scripts/phoenix_vm_configs.json"

    local PROXY_CONTAINER_NAME="docker-socket-proxy"
    local PROXY_IMAGE="haproxy:latest"
    local PROXY_PORT="2375"
    local CERT_DIR="/etc/docker/certs.d"
    local SHARED_CERT_DIR="/persistent-storage/.phoenix_certs"
    local HAPROXY_CONFIG_DIR="/etc/haproxy"
    local SHARED_SCRIPTS_DIR="/persistent-storage/.phoenix_scripts"

    # --- 1. PREPARE CERTIFICATES AND CONFIGURATION ---
    log_info "Preparing certificates and HAProxy configuration..."
    mkdir -p "${CERT_DIR}"
    mkdir -p "${HAPROXY_CONFIG_DIR}"

    # Copy certs from shared storage
    cp "${SHARED_CERT_DIR}/ca.pem" "${CERT_DIR}/ca.pem"
    cp "${SHARED_CERT_DIR}/server.crt" "${CERT_DIR}/server.crt"
    cp "${SHARED_CERT_DIR}/server.key" "${CERT_DIR}/server.key"

    # Combine cert and key for HAProxy
    cat "${CERT_DIR}/server.crt" "${CERT_DIR}/server.key" > "${CERT_DIR}/server.pem"

    # Copy HAProxy config from shared storage
    cp "${SHARED_SCRIPTS_DIR}/haproxy.cfg" "${HAPROXY_CONFIG_DIR}/haproxy.cfg"
    
    # Set appropriate permissions
    # Directories need execute permission to be accessible
    chmod 755 "${CERT_DIR}"
    chmod 644 "${CERT_DIR}/ca.pem"
    chmod 644 "${CERT_DIR}/server.crt"
    chmod 600 "${CERT_DIR}/server.key"
    chmod 644 "${CERT_DIR}/server.pem" # Allow read access for the container
 
     # --- 2. DEPLOY HAPROXY CONTAINER ---
    log_info "Deploying the HAProxy container as the Docker socket proxy..."
    
    # Stop and remove any existing proxy container to ensure a clean state
    docker rm -f "$PROXY_CONTAINER_NAME" || log_info "No existing proxy container to remove."

    # Get the Group ID of the docker socket on the host VM
    local DOCKER_GID
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    if ! [[ "$DOCKER_GID" =~ ^[0-9]+$ ]]; then
        log_fatal "Could not determine GID for /var/run/docker.sock. Cannot set permissions for proxy."
    fi
    log_info "Docker socket GID is ${DOCKER_GID}. Adding this group to the proxy container."

    local DOCKER_RUN_CMD="docker run -d --restart=always --name ${PROXY_CONTAINER_NAME} \
        --group-add ${DOCKER_GID} \
        -p ${PROXY_PORT}:2375 \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -v ${CERT_DIR}:${CERT_DIR}:ro \
        -v ${HAPROXY_CONFIG_DIR}/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro \
        ${PROXY_IMAGE}"

    if ! /bin/bash -c "$DOCKER_RUN_CMD"; then
        log_fatal "Failed to deploy the HAProxy container in VM ${VMID}."
    fi

    log_success "Docker socket proxy container is running."
 
     # --- 2. HEALTH CHECK ---
    log_info "Waiting for 2 seconds for the proxy to initialize..."
    sleep 2
    log_info "Performing health check on the socket proxy..."
    # The 'trusted_ca' feature should have already installed the CA cert system-wide.
    local VM_HOSTNAME=$(jq -r '.name' "/persistent-storage/.phoenix_scripts/vm_context.json")
    local INTERNAL_DOMAIN="internal.thinkheads.ai"
    local FQDN="${VM_HOSTNAME}.${INTERNAL_DOMAIN}"
    local HEALTH_CHECK_CMD="curl --cacert ${CERT_DIR}/ca.pem --resolve ${FQDN}:${PROXY_PORT}:127.0.0.1 https://${FQDN}:${PROXY_PORT}/_ping"
    local attempt=1
    local max_attempts=5
    local delay=5

    while [ "$attempt" -le "$max_attempts" ]; do
        log_info "Health check attempt ${attempt}/${max_attempts}..."
        http_code=$(/bin/bash -c "$HEALTH_CHECK_CMD -s -o /dev/null -w '%{http_code}'")
        if [ "$http_code" -eq 200 ]; then
            log_success "Docker socket proxy is healthy and responding with HTTP status 200."
            log_info "--- Docker Socket Proxy Installation for VMID: ${VMID} Complete ---"
            exit 0
        fi
        log_warn "Health check failed with HTTP status ${http_code}. Retrying in ${delay} seconds..."
        sleep "$delay"
        attempt=$((attempt + 1))
    done

    log_fatal "Docker socket proxy failed the health check after ${max_attempts} attempts."
}

# Pass all script arguments to the main function
main "$@"