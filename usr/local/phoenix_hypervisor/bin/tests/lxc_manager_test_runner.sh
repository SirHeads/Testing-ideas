#!/bin/bash
#
# File: lxc_manager_test_runner.sh
#
# Description: This script is the test runner for the lxc-manager.
#

set -o pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

main() {
    log_info "--- Executing lxc-manager test suite ---"
    local test_dir="${SCRIPT_DIR}/lxc"
    local all_tests_passed=true

    if [ ! -d "$test_dir" ]; then
        log_fatal "Test directory not found at '$test_dir'."
    fi

    for test_script in "$test_dir"/*.sh; do
        if [ -f "$test_script" ]; then
            log_info "--- Executing test: $(basename "$test_script") ---"
            if ! "$test_script"; then
                log_error "--- Test FAILED: $(basename "$test_script") ---"
                all_tests_passed=false
            else
                log_info "--- Test PASSED: $(basename "$test_script") ---"
            fi
        fi
    done

    if [ "$all_tests_passed" = true ]; then
        log_info "--- lxc-manager test suite PASSED ---"
        exit 0
    else
        log_error "--- lxc-manager test suite FAILED ---"
        exit 1
    fi
}

main "$@"