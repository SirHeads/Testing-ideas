#!/bin/bash
#
# File: hypervisor_feature_setup_auto_renewal.sh
# Description: This script idempotently ensures that the cron job for the
#              centralized certificate renewal manager is correctly configured.
#
# Version: 1.0.0
# Author: Roo

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." > /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Main execution ---
log_info "--- Setting up automated certificate renewal cron job ---"

CRON_JOB_COMMAND="/usr/local/phoenix_hypervisor/bin/managers/certificate-renewal-manager.sh"
CRON_JOB_SCHEDULE="0 * * * *"
CRON_FILE_PATH="/etc/cron.d/phoenix-cert-renewal"
CRON_JOB_LINE="${CRON_JOB_SCHEDULE} root ${CRON_JOB_COMMAND}"

log_info "Ensuring cron job is correctly configured in ${CRON_FILE_PATH}..."

# Create the cron job file with the correct content
echo "${CRON_JOB_LINE}" > "${CRON_FILE_PATH}"

if [ $? -eq 0 ]; then
    log_success "Successfully created/updated the certificate renewal cron job file."
    # Set appropriate permissions
    chmod 0644 "${CRON_FILE_PATH}"
else
    log_fatal "Failed to create/update the certificate renewal cron job file."
fi

# Also, clean up the user's crontab to remove any old, incorrect entries
log_info "Cleaning up old cron entries from user's crontab..."
# The following command ensures that the script doesn't fail if the user has no crontab,
# or if the crontab is empty.
(crontab -l 2>/dev/null | grep -vF "${CRON_JOB_COMMAND}" || true) | crontab -
log_info "Cleanup of user's crontab complete."

log_info "--- Automated certificate renewal setup complete ---"