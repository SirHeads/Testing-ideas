#!/bin/bash
#
# File: hypervisor_test_runner.sh
# Description: Executes all hypervisor-level verification tests.

# --- Configuration and Setup ---
set -o pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Main Logic ---
main() {
    log_info "Starting hypervisor-level verification tests..."
    local hypervisor_test_dir="${SCRIPT_DIR}/hypervisor"
    local all_tests_passed=true

    if [ ! -d "$hypervisor_test_dir" ]; then
        log_fatal "Hypervisor test directory not found at $hypervisor_test_dir."
    fi

    for test_script in "$hypervisor_test_dir"/*.sh; do
        if [ -f "$test_script" ]; then
            log_info "Executing test: $(basename "$test_script")"
            if ! "$test_script"; then
                log_error "Test failed: $(basename "$test_script")"
                all_tests_passed=false
            fi
        fi
    done

    if [ "$all_tests_passed" = true ]; then
        log_info "All hypervisor tests passed successfully."
        exit 0
    else
        log_fatal "One or more hypervisor tests failed."
    fi
}

main "$@"