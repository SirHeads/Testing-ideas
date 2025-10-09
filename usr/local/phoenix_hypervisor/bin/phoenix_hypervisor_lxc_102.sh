#!/bin/bash
#
# File: phoenix_hypervisor_lxc_102.sh
# Description: This script configures and starts the Traefik service within LXC 102.
#              It generates Traefik's main configuration, dynamic configurations for
#              internal services, and sets up a systemd service for Traefik.
#
# Arguments:
#   $1 - The CTID of the container (expected to be 102).
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: For logging and utility functions.
#   - Traefik binary (installed by feature_install_traefik.sh).
#
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID="$1"
TRAEFIK_CONFIG_DIR="/etc/traefik"
TRAEFIK_DYNAMIC_CONFIG_DIR="${TRAEFIK_CONFIG_DIR}/dynamic"
TRAEFIK_LOG_FILE="/var/log/traefik/traefik.log"
TRAEFIK_SERVICE_FILE="/etc/systemd/system/traefik.service"
CA_SERVER_URL="https://ca.internal.thinkheads.ai/acme/acme/directory"
ACME_STORAGE_FILE="${TRAEFIK_CONFIG_DIR}/acme.json"

# =====================================================================================
# Function: generate_main_config
# Description: Generates the main traefik.yml configuration file.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if file creation fails.
# =====================================================================================
generate_main_config() {
    log_info "Generating main Traefik configuration file: ${TRAEFIK_CONFIG_DIR}/traefik.yml"

    local CONFIG_CONTENT="global:
  checkNewVersion: true
  sendAnonymousUsage: false
entryPoints:
  web:
    address: \":80\"
    http:
      redirections:
        entryPoint:
          to: \"websecure\"
          scheme: \"https\"
  websecure:
    address: \":443\"
api:
  dashboard: true
  insecure: false
providers:
  file:
    directory: ${TRAEFIK_DYNAMIC_CONFIG_DIR}
    watch: true
certificatesResolvers:
  internal:
    acme:
      caServer: ${CA_SERVER_URL}
      storage: ${ACME_STORAGE_FILE}
      # No DNS challenge provider needed for internal CA, as Traefik will directly
      # communicate with Step CA's ACME endpoint.
log:
  level: INFO
  filePath: ${TRAEFIK_LOG_FILE}
accessLog:
  filePath: /var/log/traefik/access.log
"
    if ! pct exec "$CTID" -- /bin/bash -c "echo \"$CONFIG_CONTENT\" > \"${TRAEFIK_CONFIG_DIR}/traefik.yml\""; then
        log_fatal "Failed to create main Traefik configuration file in container $CTID."
    fi
    log_success "Main Traefik configuration file generated successfully."
}

# =====================================================================================
# Function: generate_dynamic_configs
# Description: Generates dynamic configuration files for internal services.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if file creation fails.
# =====================================================================================
generate_dynamic_configs() {
    log_info "Generating dynamic Traefik configuration files..."

    # --- Portainer Configuration ---
    local PORTAINER_VMID="1001" # Assuming Portainer Server is on VMID 1001
    local PORTAINER_IP=$(jq -r ".vms[] | select(.vmid == ${PORTAINER_VMID}) | .network_config.ip" "${PHOENIX_BASE_DIR}/etc/phoenix_vm_configs.json" | cut -d'/' -f1)
    local PORTAINER_PORT=$(get_global_config_value '.network.portainer_server_port')

    local PORTAINER_CONFIG_CONTENT="http:
  routers:
    portainer:
      rule: \"Host(\`portainer.internal.thinkheads.ai\`)\"
      service: portainer
      entryPoints:
        - websecure
      tls:
        certResolver: internal
  services:
    portainer:
      loadBalancer:
        servers:
          - url: \"https://${PORTAINER_IP}:${PORTAINER_PORT}\"
        # Ensure Traefik trusts the internal CA for backend communication
        serversTransport: portainer-transport
  serversTransports:
    portainer-transport:
      insecureSkipVerify: true # Temporarily skip verify, will be replaced with CA trust
      # We will later add the CA certificate here once it's bootstrapped
"
    if ! pct exec "$CTID" -- /bin/bash -c "echo \"$PORTAINER_CONFIG_CONTENT\" > \"${TRAEFIK_DYNAMIC_CONFIG_DIR}/portainer.yml\""; then
        log_fatal "Failed to create Portainer dynamic configuration file in container $CTID."
    fi
    log_success "Portainer dynamic configuration file generated."

    # --- Proxmox VE GUI Configuration ---
    local PVE_IP="10.0.0.1" # Assuming Proxmox host IP
    local PVE_PORT="8006"

    local PVE_CONFIG_CONTENT="http:
  routers:
    pve:
      rule: \"Host(\`pve.internal.thinkheads.ai\`)\"
      service: pve
      entryPoints:
        - websecure
      tls:
        certResolver: internal
  services:
    pve:
      loadBalancer:
        servers:
          - url: \"https://${PVE_IP}:${PVE_PORT}\"
        serversTransport: pve-transport
  serversTransports:
    pve-transport:
      insecureSkipVerify: true # Temporarily skip verify, will be replaced with CA trust
"
    if ! pct exec "$CTID" -- /bin/bash -c "echo \"$PVE_CONFIG_CONTENT\" > \"${TRAEFIK_DYNAMIC_CONFIG_DIR}/pve.yml\""; then
        log_fatal "Failed to create Proxmox dynamic configuration file in container $CTID."
    fi
    log_success "Proxmox dynamic configuration file generated."
}

# =====================================================================================
# Function: setup_traefik_service
# Description: Sets up and starts the systemd service for Traefik.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if service setup fails.
# =====================================================================================
setup_traefik_service() {
    log_info "Setting up systemd service for Traefik..."

    local SERVICE_CONTENT="[Unit]
Description=Traefik Reverse Proxy
After=network.target

[Service]
ExecStart=${TRAEFIK_INSTALL_DIR}/traefik --configFile=${TRAEFIK_CONFIG_DIR}/traefik.yml
Restart=always
User=root

[Install]
WantedBy=multi-user.target"

    if ! pct exec "$CTID" -- /bin/bash -c "echo \"$SERVICE_CONTENT\" > \"$TRAEFIK_SERVICE_FILE\""; then
        log_fatal "Failed to create systemd service file in container $CTID."
    fi

    if ! pct exec "$CTID" -- systemctl daemon-reload; then
        log_fatal "Failed to reload systemd daemon in container $CTID."
    fi
    if ! pct exec "$CTID" -- systemctl enable traefik; then
        log_fatal "Failed to enable traefik service in container $CTID."
    fi
    if ! pct exec "$CTID" -- systemctl start traefik; then
        log_fatal "Failed to start traefik service in container $CTID."
    fi

    if ! pct exec "$CTID" -- systemctl is-active --quiet traefik; then
        log_fatal "Traefik service is not running in container $CTID."
    fi
    log_success "Traefik service set up and started successfully."
}

# =====================================================================================
# Function: main
# Description: Main entry point for the script.
# Arguments:
#   $1 - The CTID of the container.
# Returns:
#   None.
# =====================================================================================
main() {
    if [ -z "$CTID" ]; then
        log_fatal "Usage: $0 <CTID>"
    fi

    log_info "Starting Traefik application script for CTID $CTID."

    generate_main_config
    generate_dynamic_configs
    setup_traefik_service

    log_info "Traefik application script completed for CTID $CTID."
}

# --- SCRIPT EXECUTION ---
main "$@"