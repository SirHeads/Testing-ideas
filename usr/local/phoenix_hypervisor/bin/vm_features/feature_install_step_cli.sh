#!/bin/bash
#
# File: feature_install_step_cli.sh
# Description: This feature script installs the Smallstep CLI ('step') into a VM
#              by configuring the official Smallstep APT repository. This ensures
#              a stable and maintainable installation.

set -e

# Source common utilities provided by the orchestrator
source "$(dirname "$0")/phoenix_hypervisor_common_utils.sh"

# Enable verbose logging if PHOENIX_DEBUG is set to "true"
if [ "$PHOENIX_DEBUG" == "true" ]; then
    set -x
fi

LOG_FILE="/var/log/phoenix_feature_step_cli.log"
exec &> >(tee -a "$LOG_FILE")

log_info "--- Starting Step CLI Installation via APT ---"

# Idempotency Check: Check if step CLI is already installed.
if command -v step &> /dev/null; then
    log_info "Step CLI is already installed. Skipping installation."
    exit 0
fi

# 1. Install dependencies for adding the repository
log_info "Step 1: Installing APT dependencies..."
wait_for_apt_lock
if ! apt-get update || ! apt-get install -y --no-install-recommends curl vim gpg ca-certificates; then
    log_fatal "Failed to install APT dependencies for Smallstep."
fi

# 2. Add the Smallstep APT repository
log_info "Step 2: Configuring Smallstep APT repository..."
if [ -f /etc/apt/sources.list.d/smallstep.list ]; then
    log_info "Smallstep APT repository already configured. Skipping setup."
else
    if ! (curl -fsSL https://packages.smallstep.com/keys/apt/repo-signing-key.gpg -o /etc/apt/trusted.gpg.d/smallstep.asc && \
        echo 'deb [signed-by=/etc/apt/trusted.gpg.d/smallstep.asc] https://packages.smallstep.com/stable/debian debs main' \
        | tee /etc/apt/sources.list.d/smallstep.list); then
        log_fatal "Failed to add Smallstep APT repository."
    fi
fi

# 3. Install the Step CLI package
log_info "Step 3: Installing the step-cli package..."
wait_for_apt_lock
if ! apt-get update || ! apt-get -y install step-cli; then
    log_fatal "Failed to install Smallstep CLI package."
fi

log_success "--- Step CLI Installation Complete ---"