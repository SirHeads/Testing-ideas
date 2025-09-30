#!/bin/bash

# Test Suite: Dispatcher Mixed Target Lists
# Description: Validates the dispatcher's ability to handle lists containing
#              both LXC and VM IDs, ensuring correct routing and execution order.

# Source the common test framework and utilities
source "$(dirname "$0")/../test_runner.sh"
source "$(dirname "$0")/../../phoenix_hypervisor_common_utils.sh"
source "$(dirname "$0")/../../phoenix" # Source the main dispatcher

# Mock the manager scripts to trace calls
LXC_MANAGER_CALL_LOG="/tmp/lxc_manager_call.log"
VM_MANAGER_CALL_LOG="/tmp/vm_manager_call.log"

mock_lxc_manager() {
    echo "$@" >> "$LXC_MANAGER_CALL_LOG"
}

mock_vm_manager() {
    echo "$@" >> "$VM_MANAGER_CALL_LOG"
}

# Test Case 1: Dispatch 'start' command with a mixed list
# Validates that 'phoenix start' correctly dispatches to both managers.
test_case_dispatch_mixed_start() {
    rm -f "$LXC_MANAGER_CALL_LOG" "$VM_MANAGER_CALL_LOG"
    export -f mock_lxc_manager mock_vm_manager
    export LXC_MANAGER_SCRIPT_PATH="mock_lxc_manager"
    export VM_MANAGER_SCRIPT_PATH="mock_vm_manager"

    # Dispatch a start command with a mixed list of IDs
    # LXC IDs are typically < 9000, VM IDs are >= 9000
    phoenix start 101 9001 102
    assert_success "Dispatcher should handle mixed list for 'start'."

    # Verify that the lxc-manager was called for LXC IDs
    grep -q "start 101" "$LXC_MANAGER_CALL_LOG"
    assert_success "lxc-manager should have been called for ID 101."
    grep -q "start 102" "$LXC_MANAGER_CALL_LOG"
    assert_success "lxc-manager should have been called for ID 102."

    # Verify that the vm-manager was called for the VM ID
    grep -q "start 9001" "$VM_MANAGER_CALL_LOG"
    assert_success "vm-manager should have been called for ID 9001."

    # Cleanup
    unset -f mock_lxc_manager mock_vm_manager
    unset LXC_MANAGER_SCRIPT_PATH VM_MANAGER_SCRIPT_PATH
    rm -f "$LXC_MANAGER_CALL_LOG" "$VM_MANAGER_CALL_LOG"
}

# Main execution
run_test_suite "Dispatcher Mixed Target Lists"