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
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

source "/tmp/phoenix_run/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID="$1"
CA_URL="https://ca.internal.thinkheads.ai:9000"
CA_IP="10.0.0.10" # IP of LXC 103 (Step CA)
CA_FINGERPRINT=""
MAX_RETRIES=10
RETRY_DELAY=10

# =====================================================================================
# Function: install_step_cli
# Description: Installs the Smallstep CLI tool if it's not already present.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if installation fails.
# =====================================================================================
install_step_cli() {
    if ! command -v step &> /dev/null; then
        log_info "step-cli not found in LXC $CTID. Installing..."
        log_info "Installing step-cli via Smallstep APT repository..."
        # Add Smallstep GPG key
        curl -fsSL https://packages.smallstep.com/keys/apt/repo-signing-key.gpg -o /etc/apt/trusted.gpg.d/smallstep.asc || log_fatal "Failed to download Smallstep GPG key."
        # Add Smallstep APT repository
        echo 'deb [signed-by=/etc/apt/trusted.gpg.d/smallstep.asc] https://packages.smallstep.com/stable/debian debs main' | tee /etc/apt/sources.list.d/smallstep.list > /dev/null || log_fatal "Failed to add Smallstep APT repository."
        # Update package lists and install step-cli
        apt-get update && apt-get install -y step-cli || log_fatal "Failed to install step-cli from APT repository."
        hash -r # Clear the command hash table
        # Re-check if step-cli is now available after installation
        if ! command -v step &> /dev/null; then
            log_fatal "Failed to install step-cli in LXC $CTID, or it's not in PATH after installation."
        fi
        log_info "step-cli installed successfully in LXC $CTID."
    else
        log_info "step-cli is already installed in LXC $CTID."
    fi
}

# =====================================================================================
# Function: bootstrap_step_ca
# Description: Bootstraps the step-cli with the Step CA's root certificate and fingerprint.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if bootstrapping fails.
# =====================================================================================
bootstrap_step_ca() {
    log_info "Waiting for Step CA (LXC 103 at $CA_IP) to be reachable..."
    local attempt=1
    while ! ping -c 1 "$CA_IP" > /dev/null 2>&1 && [ "$attempt" -le "$MAX_RETRIES" ]; do
        log_info "Attempt $attempt/$MAX_RETRIES: Ping to Step CA ($CA_IP) failed. Retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
        attempt=$((attempt + 1))
    done
    if [ "$attempt" -gt "$MAX_RETRIES" ]; then
        log_fatal "Step CA ($CA_IP) is not reachable after $MAX_RETRIES attempts. Cannot bootstrap step-cli."
    fi
    log_info "Step CA ($CA_IP) is reachable."

    # Add CA hostname to /etc/hosts for internal resolution
    log_info "Adding 'ca.internal.thinkheads.ai' to /etc/hosts..."
    if ! grep -q "ca.internal.thinkheads.ai" /etc/hosts; then
        echo "${CA_IP} ca.internal.thinkheads.ai" >> /etc/hosts || log_fatal "Failed to add CA entry to /etc/hosts."
    fi
    log_info "CA entry added to /etc/hosts."

    # Retrieve CA fingerprint from the mounted root certificate
    local ROOT_CA_CERT_PATH="/etc/traefik/phoenix_ca.crt" # Assuming phoenix_ca.crt is mounted here
    log_info "Checking for root CA certificate at $ROOT_CA_CERT_PATH..."
    if [ ! -f "$ROOT_CA_CERT_PATH" ]; then
        log_fatal "Root CA certificate not found at $ROOT_CA_CERT_PATH. Cannot retrieve fingerprint."
    fi
    log_info "Root CA certificate found. Retrieving fingerprint..."
    CA_FINGERPRINT=$(step certificate fingerprint "$ROOT_CA_CERT_PATH" 2>/dev/null)
    if [ -z "$CA_FINGERPRINT" ]; then
        log_fatal "Failed to retrieve fingerprint from $ROOT_CA_CERT_PATH."
    fi
    log_info "Retrieved CA Fingerprint: $CA_FINGERPRINT"

    # Add the locally mounted root CA certificate to the trust store
    log_info "Adding locally mounted root CA certificate to trust store..."
    if ! STEPDEBUG=1 step certificate install "${ROOT_CA_CERT_PATH}"; then
        log_fatal "Failed to install locally mounted root CA certificate into trust store."
    fi
    log_info "Locally mounted root CA certificate added to trust store successfully."

    # Bootstrap the step CLI with the CA's URL and fingerprint
    log_info "Bootstrapping step CLI with CA information..."
    log_info "Testing connectivity to Step CA at $CA_URL..."
    if ! curl -vk --cacert "$ROOT_CA_CERT_PATH" "$CA_URL/health" > /dev/null 2>&1; then
        log_fatal "Failed to connect to Step CA at $CA_URL. Please check network connectivity and CA service status."
    fi
    log_info "Successfully connected to Step CA."

    if ! STEPDEBUG=1 step ca bootstrap --ca-url "$CA_URL" --fingerprint "$CA_FINGERPRINT"; then
        log_fatal "Failed to bootstrap step CLI with CA information."
    fi
    log_info "step CLI bootstrapped successfully."
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

    # Create Traefik configuration directory
    mkdir -p /etc/traefik/dynamic || log_fatal "Failed to create /etc/traefik/dynamic."

    # Create traefik.yml
    cat <<EOF > /etc/traefik/traefik.yml
global:
  checkNewVersion: true
  sendAnonymousUsage: false

log:
  level: INFO

api:
  dashboard: true
  insecure: true # For internal access only, consider securing in production

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true

certificatesResolvers:
  myresolver:
    acme:
      email: admin@thinkheads.ai
      storage: /etc/traefik/acme.json
      caServer: ${CA_URL}/acme/acme/directory
      keyType: EC384
      httpChallenge:
        entryPoint: web
EOF

    # Set permissions for acme.json
    touch /etc/traefik/acme.json
    chmod 600 /etc/traefik/acme.json

    log_info "Traefik configured successfully."
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

    # Create the systemd service file content
    local SERVICE_CONTENT="[Unit]
Description=Traefik Proxy
After=network.target

[Service]
ExecStart=/usr/bin/traefik --configFile=/etc/traefik/traefik.yml
Restart=always
User=root

[Install]
WantedBy=multi-user.target"

    # Push the service file to the container
    if ! /bin/bash -c "echo \"$SERVICE_CONTENT\" > \"/etc/systemd/system/traefik.service\""; then
        log_fatal "Failed to create systemd service file in container $CTID."
    fi

    # Reload systemd, enable and start the service
    if ! systemctl daemon-reload; then
        log_fatal "Failed to reload systemd daemon in container $CTID."
    fi
    if ! systemctl enable traefik; then
        log_fatal "Failed to enable traefik service in container $CTID."
    fi
    if ! systemctl start traefik; then
        log_fatal "Failed to start traefik service in container $CTID."
    fi

    log_info "Traefik service set up and started successfully."
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

    install_step_cli
    bootstrap_step_ca
    configure_traefik
    setup_traefik_service

    log_info "Traefik application script completed for CTID $CTID."
}

# --- SCRIPT EXECUTION ---
main "$@"