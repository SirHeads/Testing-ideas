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
CA_URL="https://ca.internal.thinkheads.ai:9000"

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
    
    log_info "Traefik service started. Waiting 15 seconds for initial ACME challenge to complete..."
    sleep 15

    log_info "Reloading Traefik service to ensure it loads the new ACME certificate..."
    if ! systemctl reload traefik; then
        log_warn "Failed to reload Traefik. The service might be using a fallback certificate. Attempting a full restart..."
        systemctl restart traefik || log_error "Failed to restart Traefik after reload failed."
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

    configure_traefik
    setup_traefik_service

    log_info "Traefik application script completed for CTID $CTID."
}

# --- SCRIPT EXECUTION ---
main "$@"