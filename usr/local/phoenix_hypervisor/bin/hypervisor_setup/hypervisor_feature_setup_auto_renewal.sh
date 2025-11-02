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
CRON_JOB_SCHEDULE="0 */12 * * *"
CRON_JOB_LINE="${CRON_JOB_SCHEDULE} ${CRON_JOB_COMMAND}"

# Get current crontab content, or an empty string if it doesn't exist
CURRENT_CRON=$(crontab -l 2>/dev/null || true)

if echo "${CURRENT_CRON}" | grep -Fq "${CRON_JOB_COMMAND}"; then
    log_info "Automated certificate renewal cron job is already configured. No changes needed."
else
    log_info "Adding automated certificate renewal cron job..."
    # Add the new job to the existing cron jobs (or create a new crontab if none exists)
    (echo "${CURRENT_CRON}"; echo "${CRON_JOB_LINE}") | crontab -
    if [ $? -eq 0 ]; then
        log_success "Successfully added the certificate renewal cron job."
    else
        log_fatal "Failed to add the certificate renewal cron job."
    fi
fi

log_info "--- Automated certificate renewal setup complete ---"