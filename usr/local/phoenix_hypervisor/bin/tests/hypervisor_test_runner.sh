#!/bin/bash
#
# File: hypervisor_test_runner.sh
#
# Description: This script serves as the main entry point for executing all
#              hypervisor-level verification and validation tests. It automatically
#              discovers and runs all shell scripts located in the `hypervisor`
#              subdirectory. This runner is crucial for ensuring the stability and
#              correct configuration of the Proxmox host itself.
#
# Dependencies: - `phoenix_hypervisor_common_utils.sh` for logging functions.
#               - Test scripts located in the `./hypervisor/` directory.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if all discovered test scripts execute successfully.
#   - Exits with a non-zero status and logs a fatal error if any test script fails.
#   - Console output provides a running log of which tests are being executed
#     and their success or failure status.
#

# --- Configuration and Setup ---
# Exit immediately if a command exits with a non-zero status.
set -o pipefail
# Determine the directory of this script to reliably source other files.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
# Source shared utility functions for logging and error handling.
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Main Logic ---
# Encapsulates the primary functionality of the test runner.
main() {
    log_info "Starting all hypervisor-level verification tests..."
    # Define the directory where hypervisor-specific tests are stored.
    local hypervisor_test_dir="${SCRIPT_DIR}/hypervisor"
    # Flag to track the overall success of the test suite.
    local all_tests_passed=true

    # Check if the test directory exists.
    if [ ! -d "$hypervisor_test_dir" ]; then
        log_fatal "Hypervisor test directory not found at '$hypervisor_test_dir'."
    fi

    # Iterate over all shell scripts in the test directory.
    for test_script in "$hypervisor_test_dir"/*.sh; do
        # Ensure the item is a file before trying to execute it.
        if [ -f "$test_script" ]; then
            log_info "--- Executing test: $(basename "$test_script") ---"
            # Execute the test script. If it fails, log the failure and update the tracking flag.
            if ! "$test_script"; then
                log_error "--- Test FAILED: $(basename "$test_script") ---"
                all_tests_passed=false
            else
                log_info "--- Test PASSED: $(basename "$test_script") ---"
            fi
        fi
    done

    log_info "--- Executing hypervisor-manager test suite ---"
    if ! "${SCRIPT_DIR}/hypervisor_manager_test_runner.sh"; then
        log_error "--- Hypervisor-manager test suite FAILED ---"
        all_tests_passed=false
    else
        log_info "--- Hypervisor-manager test suite PASSED ---"
    fi

    log_info "--- Executing lxc-manager test suite ---"
    if ! "${SCRIPT_DIR}/lxc_manager_test_runner.sh"; then
        log_error "--- lxc-manager test suite FAILED ---"
        all_tests_passed=false
    else
        log_info "--- lxc-manager test suite PASSED ---"
    fi

    log_info "--- Executing vm-manager test suite ---"
    if ! "${SCRIPT_DIR}/vm_manager_test_runner.sh"; then
        log_error "--- vm-manager test suite FAILED ---"
        all_tests_passed=false
    else
        log_info "--- vm-manager test suite PASSED ---"
    fi

    # Report the final result of the test suite.
    log_info "All hypervisor verification tests passed successfully."
    exit 0
}

# --- Script Execution ---
# Pass all script arguments to the main function.
main "$@"