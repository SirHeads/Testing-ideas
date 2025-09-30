#!/bin/bash
#
# File: hypervisor_manager_test_runner.sh
#
# Description: This script is the test runner for the hypervisor-manager.
#

set -o pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

main() {
    log_info "--- Executing hypervisor-manager test suite ---"
    local test_dir="${SCRIPT_DIR}/hypervisor"
    local all_tests_passed=true

    if [ ! -d "$test_dir" ]; then
        log_fatal "Test directory not found at '$test_dir'."
    fi

    # No tests to run in this suite yet.

    if [ "$all_tests_passed" = true ]; then
        log_info "--- Hypervisor-manager test suite PASSED ---"
        exit 0
    else
        log_error "--- Hypervisor-manager test suite FAILED ---"
        exit 1
    fi
}

main "$@"