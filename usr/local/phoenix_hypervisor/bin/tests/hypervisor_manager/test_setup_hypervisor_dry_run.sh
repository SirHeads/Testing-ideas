#!/bin/bash
#
# File: test_setup_hypervisor_dry_run.sh
#
# Description: This test script validates the --dry-run functionality of the
#              hypervisor-manager.sh script. It ensures that the setup_hypervisor
#              function can be called with the --dry-run flag and that it exits
#              with a success status code, indicating that the command is recognized
#              and the script is syntactically valid.
#
# Dependencies: - `phoenix_hypervisor_common_utils.sh` for logging.
#               - `hypervisor-manager.sh` which is the script under test.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if the dry run executes successfully.
#   - Exits with status 1 if the dry run command fails.
#

# --- Configuration and Setup ---
set -o pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../../.." &> /dev/null && pwd)

# Source shared utilities
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"
MANAGER_SCRIPT="${PHOENIX_BASE_DIR}/bin/managers/hypervisor-manager.sh"

# --- Main Test Logic ---
main() {
    log_info "Starting test: setup_hypervisor --dry-run"

    # Verify the manager script exists and is executable
    if [ ! -x "$MANAGER_SCRIPT" ]; then
        log_error "Manager script not found or not executable at: $MANAGER_SCRIPT"
        exit 1
    fi

    # Execute the dry-run command and check the exit code
    if "$MANAGER_SCRIPT" setup_hypervisor --dry-run; then
        log_info "  [ PASS ] setup_hypervisor --dry-run executed successfully."
        exit 0
    else
        log_error "  [ FAIL ] setup_hypervisor --dry-run failed with a non-zero exit code."
        exit 1
    fi
}

# --- Script Execution ---
main "$@"