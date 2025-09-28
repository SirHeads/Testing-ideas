#!/bin/bash
#
# File: validate_systemic_fixes.sh
# Description: A test script to validate the systemic remediation of
#              scripting issues, specifically the enhancement of pct_exec
#              and the fix for the check_nvidia.sh scoping bug.

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Test Configuration ---
# NOTE: This test requires a running LXC container.
# Please update this CTID to a valid, non-critical container for testing.
TEST_CTID="901"

# --- Test Cases ---

# Test 1: Validate the enhanced pct_exec function
log_info "--- Running Test 1: Validate pct_exec enhancement ---"
log_info "Testing pct_exec WITHOUT the '--' separator..."
if pct_exec "$TEST_CTID" echo "Hello from test 1"; then
    log_success "Test 1a PASSED: pct_exec without '--' executed successfully."
else
    log_fatal "Test 1a FAILED: pct_exec without '--' failed."
fi

log_info "Testing pct_exec WITH the '--' separator..."
if pct_exec "$TEST_CTID" -- echo "Hello from test 2"; then
    log_success "Test 1b PASSED: pct_exec with '--' executed successfully."
else
    log_fatal "Test 1b FAILED: pct_exec with '--' failed."
fi
log_info "--- Test 1 Complete ---"

# Test 2: Validate the fix for check_nvidia.sh
log_info "--- Running Test 2: Validate check_nvidia.sh fix ---"
log_info "Executing the corrected check_nvidia.sh script..."
if "${SCRIPT_DIR}/../health_checks/check_nvidia.sh" "$TEST_CTID"; then
    log_success "Test 2 PASSED: check_nvidia.sh executed successfully."
else
    log_fatal "Test 2 FAILED: check_nvidia.sh failed."
fi
log_info "--- Test 2 Complete ---"

log_info "All validation tests passed successfully."
exit 0