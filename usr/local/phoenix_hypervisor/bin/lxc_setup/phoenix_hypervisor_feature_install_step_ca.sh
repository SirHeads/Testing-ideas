#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_step_ca.sh
# Description: This script installs the Smallstep CLI and Smallstep CA binaries
#              within an LXC container. It is designed to be idempotent.
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
# Determine the absolute path of the script's directory to ensure reliable
# sourcing of other scripts, regardless of where this script is called from.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID="$1"

# =====================================================================================
# Function: setup_smallstep_repo
# Description: Sets up the Smallstep APT repository.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if setup fails.
# =====================================================================================
setup_smallstep_repo() {
    log_info "Setting up Smallstep APT repository..."
    if pct exec "$CTID" -- test -f /etc/apt/sources.list.d/smallstep.list; then
        log_info "Smallstep APT repository already configured. Skipping."
        return 0
    fi

    if ! pct exec "$CTID" -- /bin/bash -c "apt-get update && apt-get install -y --no-install-recommends curl vim gpg ca-certificates"; then
        log_fatal "Failed to install APT dependencies for Smallstep in container $CTID."
    fi

    if ! pct exec "$CTID" -- /bin/bash -c "curl -fsSL https://packages.smallstep.com/keys/apt/repo-signing-key.gpg -o /etc/apt/trusted.gpg.d/smallstep.asc && \
        echo 'deb [signed-by=/etc/apt/trusted.gpg.d/smallstep.asc] https://packages.smallstep.com/stable/debian debs main' \
        | tee /etc/apt/sources.list.d/smallstep.list"; then
        log_fatal "Failed to add Smallstep APT repository in container $CTID."
    fi

    if ! pct exec "$CTID" -- apt-get update; then
        log_fatal "Failed to update APT packages after adding Smallstep repository in container $CTID."
    fi
    log_success "Smallstep APT repository setup complete."
}

# =====================================================================================
# Function: install_step_cli
# Description: Installs the Smallstep CLI.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if installation fails.
# =====================================================================================
install_step_cli() {
    log_info "Installing Smallstep CLI..."
    if pct exec "$CTID" -- test -f /usr/bin/step; then
        log_info "Smallstep CLI already installed. Skipping."
        return 0
    fi

    setup_smallstep_repo

    if ! pct exec "$CTID" -- apt-get -y install step-cli; then
        log_fatal "Failed to install Smallstep CLI in container $CTID."
    fi
    log_success "Smallstep CLI installed successfully."
}

# =====================================================================================
# Function: install_step_ca
# Description: Installs the Smallstep CA.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if installation fails.
# =====================================================================================
install_step_ca() {
    log_info "Installing Smallstep CA..."
    if pct exec "$CTID" -- test -f /usr/bin/step-ca; then
        log_info "Smallstep CA already installed. Skipping."
        return 0
    fi

    setup_smallstep_repo

    if ! pct exec "$CTID" -- apt-get -y install step-ca; then
        log_fatal "Failed to install Smallstep CA in container $CTID."
    fi
    log_success "Smallstep CA installed successfully."
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

    log_info "Starting Step CA feature installation for CTID $CTID."

    install_step_cli
    install_step_ca

    log_info "Step CA feature installation completed for CTID $CTID."
}

# --- SCRIPT EXECUTION ---
main "$@"