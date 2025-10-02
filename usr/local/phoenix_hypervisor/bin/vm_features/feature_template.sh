#!/bin/bash
set -e

# Log file for feature script execution.
LOG_FILE="/var/log/phoenix_feature_template.log"
exec &> >(tee -a "$LOG_FILE")

echo "--- Starting Feature Template Script ---"

# Source the common utilities script
# The script will be available at /tmp/phoenix_feature_run/phoenix_hypervisor_common_utils.sh within the VM
if [ -f "/tmp/phoenix_feature_run/phoenix_hypervisor_common_utils.sh" ]; then
    source "/tmp/phoenix_feature_run/phoenix_hypervisor_common_utils.sh"
else
    echo "Error: Common utilities script not found." >&2
    exit 1
fi

# Log the start of the feature installation
log_info "Starting feature_template.sh script..."

# Idempotency Check: Check if the feature is already installed.
log_info "Checking for existing feature installation..."
if [ -f "/opt/feature_installed.flag" ]; then
    log_info "Feature already installed. Skipping."
    exit 0
fi
log_info "No existing installation found. Proceeding."

# Main installation logic goes here.
log_info "Step 1: Installing feature..."

# For demonstration, we'll just create a flag file.
if ! touch /opt/feature_installed.flag; then
    log_fatal "Failed to create the feature flag file."
fi
log_info "Feature installed successfully."

# Log the completion of the feature installation
log_info "feature_template.sh script finished."

echo "--- Feature Template Script Complete ---"

exit 0