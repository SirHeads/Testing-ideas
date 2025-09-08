#!/bin/bash

# Source the common utilities script
source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh

# Function to log messages
log_message "Setting up Python API Service environment..."

# Update package lists
log_message "Updating package lists..."
pct exec $LXC_ID -- apt-get update

# Install Python, pip, and venv
log_message "Installing Python 3, pip, and venv..."
pct exec $LXC_ID -- apt-get install -y python3 python3-pip python3-venv python3.10-venv

log_message "Python API Service environment setup complete."