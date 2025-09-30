# Legacy Test Migration Plan

This document outlines the plan to migrate our legacy testing scripts into the new, unified testing framework.

## 1. Migration Strategy

*   **vLLM Container Tests (LXC 950, 951, etc.):**
    *   The Python-based vLLM tests (`test_vllm_context_window.py`, `test_vllm_responsiveness.py`) will be integrated as `integration_tests` for the vLLM containers.
    *   This will be done by adding a new `integration_tests` suite to the `tests` object for each vLLM container in `phoenix_lxc_configs.json`.

*   **Hypervisor-Level Tests:**
    *   The `phoenix_hypervisor_tests.sh` and `validate_systemic_fixes.sh` scripts, which test the host environment, will be managed by a new, dedicated test runner.
    *   This keeps host-level validation separate from container-specific testing.

## 2. New `hypervisor_test_runner.sh` Script

A new script will be created at `usr/local/phoenix_hypervisor/bin/tests/hypervisor_test_runner.sh`. This script will provide a single, convenient entry point for executing all host-level verification tests.

### Full Script Contents:

```bash
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
```

## 3. Implementation Steps

1.  Create the `hypervisor_test_runner.sh` script with the contents above.
2.  Make the new script executable.
3.  Modify `phoenix_lxc_configs.json` to add the `integration_tests` suite to the vLLM containers.

This plan provides a clear path forward for integrating our legacy tests into the new, more robust framework.