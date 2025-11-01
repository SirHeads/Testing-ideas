#!/bin/bash
#
# File: phoenix_hypervisor_lxc_102.sh
# Description: Self-contained setup for Traefik Internal Proxy in LXC 102.
#              Installs step-cli, bootstraps with Step CA, configures Traefik,
#              and starts the service.
#
# Arguments:
#   $1 - The CTID of the container (expected to be 102).
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: For logging and utility functions.
#   - step-cli and step-ca binaries (installed by feature_install_step_ca.sh).
#
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

set -e

# --- SCRIPT INITIALIZATION ---
source "/tmp/phoenix_run/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID="$1"
CA_URL="https://10.0.0.10:9000"

CA_READY_FILE="/etc/step-ca/ssl/ca.ready"
PROVISIONER_PASSWORD_FILE="/etc/step-ca/ssl/provisioner_password.txt"
ROOT_CA_CERT="/usr/local/share/ca-certificates/phoenix_root_ca.crt"
TRAEFIK_CERT_DIR="/etc/traefik/certs"
TRAEFIK_CERT_FILE="${TRAEFIK_CERT_DIR}/traefik.internal.thinkheads.ai.crt"
TRAEFIK_KEY_FILE="${TRAEFIK_CERT_DIR}/traefik.internal.thinkheads.ai.key"

# =====================================================================================
# Function: wait_for_ca
# Description: Waits for the Step CA to be ready by checking for a file.
# =====================================================================================
wait_for_ca() {
   log_info "Waiting for Step CA to become ready..."
   while [ ! -f "${CA_READY_FILE}" ]; do
       log_info "CA not ready yet. Waiting 5 seconds..."
       sleep 5
   done
   log_success "Step CA is ready."
}

# =====================================================================================
# Function: bootstrap_step_cli
# Description: Bootstraps the step CLI to trust the internal CA.
# =====================================================================================
bootstrap_step_cli() {
   log_info "Bootstrapping Step CLI..."
   # Use the direct IP address for the initial bootstrap to bypass DNS resolution issues.
   if ! step ca bootstrap --ca-url "https://10.0.0.10:9000" --fingerprint "$(step certificate fingerprint ${ROOT_CA_CERT})" --force; then
       log_fatal "Failed to bootstrap Step CLI."
   fi
   log_success "Step CLI bootstrapped successfully."
}

# =====================================================================================
# Function: request_traefik_certificate
# Description: Requests a TLS certificate for Traefik from the Step CA.
# =====================================================================================
request_traefik_certificate() {
   log_info "Requesting Traefik dashboard certificate..."
   mkdir -p "${TRAEFIK_CERT_DIR}"
   
   if ! step ca certificate traefik.internal.thinkheads.ai "${TRAEFIK_CERT_FILE}" "${TRAEFIK_KEY_FILE}" --provisioner "admin@thinkheads.ai" --provisioner-password-file "${PROVISIONER_PASSWORD_FILE}" --force; then
       log_fatal "Failed to obtain Traefik certificate."
   fi
   log_success "Traefik certificate obtained successfully."
}

# =====================================================================================
# Function: configure_traefik
# Description: Configures Traefik with entrypoints and ACME provider.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if configuration fails.
# =====================================================================================
configure_traefik() {
    log_info "Configuring Traefik..."

    # Wipe and recreate Traefik dynamic configuration directory
    log_info "Ensuring Traefik dynamic configuration directory exists and has correct permissions..."
    mkdir -p /etc/traefik/dynamic || log_fatal "Failed to create /etc/traefik/dynamic."
    chmod 755 /etc/traefik/dynamic || log_warn "Failed to set permissions on /etc/traefik/dynamic."

    # Copy the Traefik template and replace the CA_URL placeholder
    log_info "Copying Traefik configuration template..."
    cp "/tmp/phoenix_run/traefik.yml.template" "/etc/traefik/traefik.yml" || log_fatal "Failed to copy Traefik template."

    log_info "Injecting CA URL into Traefik configuration..."
    sed -i "s|__CA_URL__|${CA_URL}|g" "/etc/traefik/traefik.yml" || log_fatal "Failed to inject CA URL."
 
     # Force a fresh certificate request by deleting the old acme.json
     log_info "Removing existing acme.json to force fresh certificate request..."
     rm -f /etc/traefik/acme.json
 
     # Set permissions for acme.json
     touch /etc/traefik/acme.json
     chmod 600 /etc/traefik/acme.json
 
     # Create dynamic configuration for the dashboard
    cat <<'EOF' > /etc/traefik/dynamic/dashboard.yml
http:
  middlewares:
    https-redirect:
      redirectScheme:
        scheme: https
        permanent: true

  routers:
    web-redirect:
      rule: "HostRegexp(`{host:.+}`)"
      entryPoints:
        - web
      middlewares:
        - https-redirect
      service: "noop@internal"

    dashboard:
      rule: "Host(`traefik.internal.thinkheads.ai`)"
      service: "api@internal"
      entryPoints:
        - websecure
      tls:
        certResolver: internal-resolver

    dashboard-insecure:
      rule: "Host(`localhost`) && PathPrefix(`/dashboard`) || PathPrefix(`/api`)"
      service: "api@internal"
      entryPoints:
        - traefik
EOF

    # Dynamic configuration is now handled by the sync_all command at the host level.
    log_info "Traefik static configuration complete."
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
    log_info "Starting Traefik service..."

    if ! systemctl restart traefik; then
        log_fatal "Failed to restart traefik service in container $CTID."
    fi

    log_info "Traefik service setup complete."
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

    wait_for_ca
    bootstrap_step_cli
    request_traefik_certificate
    configure_traefik
    setup_traefik_service

    log_info "Traefik application script completed for CTID $CTID."
}

# --- SCRIPT EXECUTION ---
main "$@"