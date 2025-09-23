#!/bin/bash

# Source the common utilities script
source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh

if [ "$#" -ne 1 ]; then
    log_error "Usage: $0 <CTID>"
    exit_script 2
fi
CTID="$1"

log_info "Starting Python API Service feature installation for CTID: $CTID"

if is_feature_installed "$CTID" "python_api_service"; then
    log_info "Python API Service feature is already installed. Skipping."
    exit_script 0
fi

# Update package lists
log_info "Updating package lists..."
pct_exec "$CTID" apt-get update

# Install Python, pip, and venv
log_info "Installing Python 3, pip, and venv..."
pct_exec "$CTID" apt-get install -y python3 python3-pip python3-venv python3.10-venv

log_info "Python API Service environment setup complete."
exit_script 0