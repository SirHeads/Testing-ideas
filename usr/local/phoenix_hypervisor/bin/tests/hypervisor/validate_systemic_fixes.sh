#!/bin/bash
#
# File: validate_systemic_fixes.sh
#
# Description: This script is a regression test designed to validate specific,
#              system-wide code improvements. It confirms that:
#              1. The `pct_exec` utility function correctly handles commands both
#                 with and without the `--` separator.
#              2. The `check_nvidia.sh` health check script operates correctly
#                 after a scoping bug was fixed.
#              This type of targeted validation is crucial for ensuring that bug
#              fixes do not introduce new problems.
#
# Dependencies: - `phoenix_hypervisor_common_utils.sh` for logging and `pct_exec`.
#               - A running, non-critical LXC container to serve as a test target.
#               - The `check_nvidia.sh` script must be present.
#
# Inputs:
#   - The `TEST_CTID` variable must be set to the ID of a valid, running LXC container.
#
# Outputs:
#   - Exits with status 0 if all validation tests pass.
#   - Exits with a non-zero status if any test fails.
#   - Console output provides detailed logs of each test case.
#

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../../phoenix_hypervisor_common_utils.sh"

# --- Test Configuration ---
# NOTE: This test requires a running LXC container.
# Please update this CTID to a valid, non-critical container for testing.
TEST_CTID="901"

# --- Test Cases ---

# Test 1: Validate the enhanced pct_exec function.
# This test ensures that the wrapper function for `pct exec` can handle commands
# correctly, which is fundamental to container orchestration.
    # Start the test container
    log_info "Starting test container $TEST_CTID..."
    pct start "$TEST_CTID" || log_fatal "Failed to start test container $TEST_CTID."

log_info "--- Running Test 1: Validate pct_exec enhancement ---"
log_info "Testing pct_exec WITHOUT the '--' separator..."
if pct_exec "$TEST_CTID" echo "Hello from test 1"; then
    log_success "Test 1a PASSED: pct_exec without '--' executed successfully."
else
    log_fatal "Test 1a FAILED: pct_exec without '--' failed."
fi

log_info "Testing pct_exec WITH the '--' separator for command robustness..."
if pct_exec "$TEST_CTID" -- echo "Hello from test 2"; then
    log_success "Test 1b PASSED: pct_exec with '--' executed successfully."
else
    log_fatal "Test 1b FAILED: pct_exec with '--' failed."
fi
log_info "--- Test 1 Complete ---"

# Test 2: Validate the fix for the check_nvidia.sh script.
# This test runs the NVIDIA health check to confirm that a previously identified
# variable scoping bug has been resolved and the script now runs without error.
log_info "--- Running Test 2: Validate check_nvidia.sh fix ---"
log_info "Executing the corrected check_nvidia.sh script against CTID ${TEST_CTID}..."
if "${SCRIPT_DIR}/../../health_checks/check_nvidia.sh" "$TEST_CTID"; then
    log_success "Test 2 PASSED: check_nvidia.sh executed successfully, confirming bug fix."
else
    log_fatal "Test 2 FAILED: check_nvidia.sh failed to execute."
fi
log_info "--- Test 2 Complete ---"

    # Stop the test container
    log_info "Stopping test container $TEST_CTID..."
    pct stop "$TEST_CTID" || log_warn "Failed to stop test container $TEST_CTID."

log_info "All systemic fix validation tests passed successfully."
exit 0