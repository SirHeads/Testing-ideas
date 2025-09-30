#!/bin/bash

# Test Suite: VM Manager Core Functionality
# Description: Validates the core CRUD (Create, Read, Update, Delete)
#              operations of the vm-manager.sh script.

# Source the common test framework and utilities
source "$(dirname "$0")/../test_runner.sh"
source "$(dirname "$0")/../../phoenix_hypervisor_common_utils.sh"
VM_MANAGER_SCRIPT="$(dirname "$0")/../../managers/vm-manager.sh"

# Test Case 1: Create a new VM
# Validates that a new VM can be created successfully.
test_case_vm_creation() {
    # Define a test VM configuration
    local vm_id="9001"
    local vm_name="test-vm-creation"
    local temp_vm_config_file="/tmp/test_vm_crud_config.json"

    # Create a temporary VM config
    jq -n --arg vmid "$vm_id" --arg name "$vm_name" \
      '{vms: [{vmid: $vmid, name: $name, cores: 1, memory: 1024, "disk-size": "10G"}]}' \
      > "$temp_vm_config_file"

    # Create the VM
    "$VM_MANAGER_SCRIPT" "create" "$vm_id" --config "$temp_vm_config_file"
    assert_success "VM Creation for ID $vm_id should succeed."

    # Verify the VM exists
    qm status "$vm_id" &>/dev/null
    assert_success "VM ID $vm_id should exist after creation."
}

# Test Case 2: Delete a VM
# Validates that an existing VM can be deleted successfully.
test_case_vm_deletion() {
    local vm_id="9002"
    local vm_name="test-vm-deletion"
    local vm_config_json

    # Create a temporary VM for deletion test
    local temp_vm_config_file="/tmp/test_vm_crud_config.json"
    jq -n --arg vmid "$vm_id" --arg name "$vm_name" \
      '{vms: [{vmid: $vmid, name: $name, cores: 1, memory: 1024, "disk-size": "10G"}]}' \
      > "$temp_vm_config_file"
    "$VM_MANAGER_SCRIPT" "create" "$vm_id" --config "$temp_vm_config_file"

    # Delete the VM
    "$VM_MANAGER_SCRIPT" "delete" "$vm_id" --config "$temp_vm_config_file"
    assert_success "VM Deletion for ID $vm_id should succeed."

    # Verify the VM is gone
    ! qm status "$vm_id" &>/dev/null
    assert_success "VM ID $vm_id should not exist after deletion."
}

# Test Case 3: Start and Stop a VM
# Validates that a VM can be started and stopped.
test_case_vm_start_stop() {
    local vm_id="9003"
    local vm_name="test-vm-start-stop"
    local vm_config_json

    # Create a temporary VM
    vm_config_json=$(jq -n \
        --arg name "$vm_name" \
        --arg cores "1" \
        --arg memory "1024" \
        --arg disk_size "10G" \
        '{name: $name, cores: $cores, memory: $memory, "disk-size": $disk_size}')
    
    local temp_vm_config_file="/tmp/test_vm_crud_config.json"
    jq -n --arg vmid "$vm_id" --arg name "$vm_name" \
      '{vms: [{vmid: $vmid, name: $name, cores: 1, memory: 1024, "disk-size": "10G"}]}' \
      > "$temp_vm_config_file"
    "$VM_MANAGER_SCRIPT" "create" "$vm_id" --config "$temp_vm_config_file"

    # Start the VM
    "$VM_MANAGER_SCRIPT" "start" "$vm_id" --config "$temp_vm_config_file"
    assert_success "Starting VM ID $vm_id should succeed."
    assert_equal "$(qm status "$vm_id" | awk '{print $2}')" "running" "VM ID $vm_id should be running."

    # Stop the VM
    "$VM_MANAGER_SCRIPT" "stop" "$vm_id" --config "$temp_vm_config_file"
    assert_success "Stopping VM ID $vm_id should succeed."
    assert_equal "$(qm status "$vm_id" | awk '{print $2}')" "stopped" "VM ID $vm_id should be stopped."

    # Cleanup
    "$VM_MANAGER_SCRIPT" "delete" "$vm_id" --config "$temp_vm_config_file"
    rm -f "$temp_vm_config_file"
}

# Main execution
run_test_suite "VM Manager CRUD Operations"