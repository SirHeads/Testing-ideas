#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_traefik.sh
# Description: This script downloads and installs the Traefik binary within an LXC container.
#              It also sets up necessary directories and permissions.
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
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../" &> /dev/null && pwd)

source "${PHOENIX_BASE_DIR}/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID="$1"
TRAEFIK_VERSION="v3.0.0"
TRAEFIK_DOWNLOAD_URL="https://github.com/traefik/traefik/releases/download/${TRAEFIK_VERSION}/traefik_${TRAEFIK_VERSION}_linux_amd64.tar.gz"
TRAEFIK_INSTALL_DIR="/usr/local/bin"
TRAEFIK_CONFIG_DIR="/etc/traefik"
TRAEFIK_LOG_DIR="/var/log/traefik"

# =====================================================================================
# Function: install_traefik_binary
# Description: Downloads and installs the Traefik binary.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if installation fails.
# =====================================================================================
install_traefik_binary() {
    log_info "Installing Traefik binary..."

    if pct exec "$CTID" -- test -f "${TRAEFIK_INSTALL_DIR}/traefik"; then
        log_info "Traefik binary already installed. Skipping."
        return 0
    fi

    local TEMP_DIR="/tmp/traefik_install"
    if ! pct exec "$CTID" -- mkdir -p "$TEMP_DIR"; then
        log_fatal "Failed to create temporary directory in container $CTID."
    fi

    log_info "Downloading Traefik from ${TRAEFIK_DOWNLOAD_URL}..."
    if ! pct exec "$CTID" -- /usr/bin/wget -O "${TEMP_DIR}/traefik.tar.gz" "$TRAEFIK_DOWNLOAD_URL"; then
        log_fatal "Failed to download Traefik binary in container $CTID."
    fi

    log_info "Extracting Traefik binary..."
    if ! pct exec "$CTID" -- /bin/tar -xzf "${TEMP_DIR}/traefik.tar.gz" -C "$TEMP_DIR"; then
        log_fatal "Failed to extract Traefik binary in container $CTID."
    fi

    log_info "Removing default configuration files from extracted tarball..."
    if ! pct exec "$CTID" -- /bin/rm -f "${TEMP_DIR}/traefik.yml" "${TEMP_DIR}/dashboard.yml"; then
        log_warn "Could not remove default configuration files. They may not exist in this version."
    fi

    log_info "Installing Traefik binary to ${TRAEFIK_INSTALL_DIR}..."
    if ! pct exec "$CTID" -- /usr/bin/install -m 755 "${TEMP_DIR}/traefik" "${TRAEFIK_INSTALL_DIR}/traefik"; then
        log_fatal "Failed to install Traefik binary to ${TRAEFIK_INSTALL_DIR} in container $CTID."
    fi

    log_info "Cleaning up temporary files..."
    if ! pct exec "$CTID" -- /bin/rm -rf "$TEMP_DIR"; then
        log_warn "Failed to clean up temporary directory in container $CTID."
    fi

    log_success "Traefik binary installed successfully."
}

# =====================================================================================
# Function: setup_traefik_directories
# Description: Sets up necessary directories and permissions for Traefik.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if directory setup fails.
# =====================================================================================
setup_traefik_directories() {
    log_info "Setting up Traefik directories and permissions..."

    if ! pct exec "$CTID" -- mkdir -p "$TRAEFIK_CONFIG_DIR"; then
        log_fatal "Failed to create Traefik config directory in container $CTID."
    fi
    if ! pct exec "$CTID" -- mkdir -p "${TRAEFIK_CONFIG_DIR}/dynamic"; then
        log_fatal "Failed to create Traefik dynamic config directory in container $CTID."
    fi
    if ! pct exec "$CTID" -- mkdir -p "$TRAEFIK_LOG_DIR"; then
        log_fatal "Failed to create Traefik log directory in container $CTID."
    fi

    # Set appropriate permissions
    if ! pct exec "$CTID" -- chmod 755 "$TRAEFIK_CONFIG_DIR"; then
        log_fatal "Failed to set permissions for Traefik config directory in container $CTID."
    fi
    if ! pct exec "$CTID" -- chmod 755 "${TRAEFIK_CONFIG_DIR}/dynamic"; then
        log_fatal "Failed to set permissions for Traefik dynamic config directory in container $CTID."
    fi
    if ! pct exec "$CTID" -- chmod 755 "$TRAEFIK_LOG_DIR"; then
        log_fatal "Failed to set permissions for Traefik log directory in container $CTID."
    fi

    log_success "Traefik directories and permissions set up successfully."
}

# =====================================================================================
# Function: setup_traefik_tls
# Description: Generates a client certificate for Traefik and places it along with the CA
#              certificate in the appropriate directory for mTLS with the Docker Proxy.
# =====================================================================================
setup_traefik_tls() {
    log_info "Setting up TLS for Traefik Docker provider..."
    local CERT_DIR="/etc/traefik/certs"
    local FQDN="traefik.internal.thinkheads.ai"
    local INTERNAL_FQDN="traefik.internal.thinkheads.ai"
    local BOOTSTRAP_CA_URL="$2"
    local FINAL_CA_URL="https://ca.internal.thinkheads.ai:9000"
    local ROOT_CA_CERT_SHARED="/etc/step-ca/ssl/phoenix_root_ca.crt"
    local PROVISIONER_PASSWORD_FILE="/etc/step-ca/ssl/provisioner_password.txt"

    pct exec "$CTID" -- mkdir -p "$CERT_DIR"

    # Bootstrap the step CLI within the Traefik container
    log_info "Bootstrapping Step CLI inside Traefik container..."
    local ca_url_to_use="${BOOTSTRAP_CA_URL:-$FINAL_CA_URL}"
    pct exec "$CTID" -- /bin/bash -c "step ca bootstrap --ca-url \"${ca_url_to_use}\" --fingerprint \"\$(step certificate fingerprint ${ROOT_CA_CERT_SHARED})\" --force"

    # Generate Client Certificate inside the Traefik container
    log_info "Generating client certificate for ${FQDN} inside Traefik container..."
    pct exec "$CTID" -- step ca certificate "${FQDN}" "${CERT_DIR}/cert.pem" "${CERT_DIR}/key.pem" --san "${INTERNAL_FQDN}" \
        --provisioner admin@thinkheads.ai \
        --provisioner-password-file "${PROVISIONER_PASSWORD_FILE}" --force

    # Transfer the root CA certificate using a robust pull/push method
    log_info "Transferring root CA to ${CERT_DIR}/ca.pem..."
    local HOST_TEMP_CA="/tmp/traefik_ca_${CTID}.pem"
    pct pull "$CTID" "${ROOT_CA_CERT_SHARED}" "$HOST_TEMP_CA"
    pct push "$CTID" "$HOST_TEMP_CA" "${CERT_DIR}/ca.pem"
    rm -f "$HOST_TEMP_CA"

    log_success "TLS certificates for Traefik Docker provider installed successfully."
}

# =====================================================================================
# Function: push_static_config
# Description: Generates the static traefik.yml from a template and pushes it to the container.
# =====================================================================================
push_static_config() {
    log_info "Generating and pushing static Traefik configuration..."

    local template_file="${PHOENIX_BASE_DIR}/../etc/traefik/traefik.yml.template"
    if [ ! -f "$template_file" ]; then
        log_fatal "Traefik configuration template not found at ${template_file}."
    fi

    # Create a temporary file for the processed config
    local temp_config_file
    temp_config_file=$(mktemp)

    # Replace placeholder in the template with the actual CA URL
    cp "$template_file" "$temp_config_file"

    log_info "Pushing generated traefik.yml to ${TRAEFIK_CONFIG_DIR}/traefik.yml in container $CTID..."
    if ! pct push "$CTID" "$temp_config_file" "${TRAEFIK_CONFIG_DIR}/traefik.yml"; then
        rm "$temp_config_file"
        log_fatal "Failed to push traefik.yml to container $CTID."
    fi

    # Set correct permissions on the config file inside the container
    if ! pct exec "$CTID" -- chmod 644 "${TRAEFIK_CONFIG_DIR}/traefik.yml"; then
        log_warn "Failed to set permissions on traefik.yml in container $CTID."
    fi

    rm "$temp_config_file" # Clean up the temporary file
    log_success "Static Traefik configuration pushed successfully."
}

# =====================================================================================
# Function: create_systemd_service
# Description: Creates and enables a systemd service for Traefik.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if service setup fails.
# =====================================================================================
create_systemd_service() {
    log_info "Creating systemd service for Traefik..."

    local service_file_content="[Unit]
Description=Traefik Ingress Controller
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${TRAEFIK_INSTALL_DIR}/traefik --configfile=${TRAEFIK_CONFIG_DIR}/traefik.yml
ExecReload=/usr/bin/pkill -HUP traefik
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target"

    # Create a temporary file on the host
    local temp_service_file
    temp_service_file=$(mktemp)
    echo "$service_file_content" > "$temp_service_file"

    log_info "Pushing systemd service file to container..."
    if ! pct push "$CTID" "$temp_service_file" /etc/systemd/system/traefik.service; then
        rm "$temp_service_file"
        log_fatal "Failed to push systemd service file to container $CTID."
    fi
    rm "$temp_service_file" # Clean up the temporary file

    log_info "Reloading systemd daemon..."
    if ! pct exec "$CTID" -- systemctl daemon-reload; then
        log_fatal "Failed to reload systemd daemon in container $CTID."
    fi

    log_info "Enabling Traefik service..."
    if ! pct exec "$CTID" -- systemctl enable traefik; then
        log_fatal "Failed to enable Traefik service in container $CTID."
    fi

    log_success "Traefik systemd service created and enabled successfully."
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

    log_info "Starting Traefik feature installation for CTID $CTID."

    install_traefik_binary
    setup_traefik_directories
    setup_traefik_tls "$@"
    push_static_config
    create_systemd_service

    log_info "Traefik service has been enabled, but will not be started until the 'phoenix sync all' command is run."

    log_info "Traefik feature installation completed for CTID $CTID."
}

# --- SCRIPT EXECUTION ---
main "$@"