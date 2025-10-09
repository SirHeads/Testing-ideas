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
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../../.." &> /dev/null && pwd)

source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID="$1"
TRAEFIK_VERSION="v3.5.3"
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

    log_info "Moving Traefik binary to ${TRAEFIK_INSTALL_DIR}..."
    if ! pct exec "$CTID" -- /bin/mv "${TEMP_DIR}/traefik" "$TRAEFIK_INSTALL_DIR/"; then
        log_fatal "Failed to move Traefik binary to install directory in container $CTID."
    fi

    log_info "Setting permissions for Traefik binary..."
    if ! pct exec "$CTID" -- /bin/chmod +x "${TRAEFIK_INSTALL_DIR}/traefik"; then
        log_fatal "Failed to set executable permissions for Traefik binary in container $CTID."
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

    log_info "Traefik feature installation completed for CTID $CTID."
}

# --- SCRIPT EXECUTION ---
main "$@"