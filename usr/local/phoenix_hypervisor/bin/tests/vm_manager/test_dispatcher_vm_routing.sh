#!/bin/bash

# Test Suite: Dispatcher VM Command Routing
# Description: Validates that the main dispatcher correctly routes VM-related
#              commands to the vm-manager.sh script.

# Source the common test framework and utilities
source "$(dirname "$0")/../test_runner.sh"
source "$(dirname "$0")/../../phoenix_hypervisor_common_utils.sh"
source "$(dirname "$0")/../../phoenix" # Source the main dispatcher

# Mock the vm-manager.sh to trace calls
VM_MANAGER_CALL_LOG="/tmp/vm_manager_call.log"
mock_vm_manager() {
    echo "$@" >> "$VM_MANAGER_CALL_LOG"
}

# Test Case 1: Dispatch 'create' command for a VM
# Validates that 'phoenix create vm' is routed to the vm-manager.
test_case_dispatch_create_vm() {
    rm -f "$VM_MANAGER_CALL_LOG"
    # Replace the real vm-manager with our mock function
    export -f mock_vm_manager
    export VM_MANAGER_SCRIPT_PATH="mock_vm_manager"

    # Dispatch a create command for a VM
    phoenix create 9004 --type vm
    assert_success "Dispatcher should successfully handle 'create vm'."

    # Verify that the vm-manager was called with the correct arguments
    local expected_call="create 9004"
    grep -q "$expected_call" "$VM_MANAGER_CALL_LOG"
    assert_success "vm-manager should have been called with 'create 9004'."

    # Cleanup
    unset -f mock_vm_manager
    unset VM_MANAGER_SCRIPT_PATH
    rm -f "$VM_MANAGER_CALL_LOG"
}

# Test Case 2: Dispatch 'delete' command for a VM
# Validates that 'phoenix delete vm' is routed to the vm-manager.
test_case_dispatch_delete_vm() {
    rm -f "$VM_MANAGER_CALL_LOG"
    export -f mock_vm_manager
    export VM_MANAGER_SCRIPT_PATH="mock_vm_manager"

    phoenix delete 9005 --type vm
    assert_success "Dispatcher should successfully handle 'delete vm'."

    local expected_call="delete 9005"
    grep -q "$expected_call" "$VM_MANAGER_CALL_LOG"
    assert_success "vm-manager should have been called with 'delete 9005'."

    unset -f mock_vm_manager
    unset VM_MANAGER_SCRIPT_PATH
    rm -f "$VM_MANAGER_CALL_LOG"
}

# Main execution
run_test_suite "Dispatcher VM Routing"