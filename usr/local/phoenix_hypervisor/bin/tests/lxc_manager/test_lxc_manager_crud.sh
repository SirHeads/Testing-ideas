#!/bin/bash
#
# ==============================================================================
#
# File: test_lxc_manager_crud.sh
#
# Description:
#   This script contains a suite of tests for the basic CRUD (Create, Read,
#   Update, Delete) functionality of the `lxc-manager.sh` script. It is a
#   critical test for ensuring the fundamental lifecycle management of LXC
#   containers is working as expected. The script verifies that containers can
#   be created, started, stopped, and deleted correctly.
#
# Dependencies:
#   - `phoenix_hypervisor_common_utils.sh`: For standardized logging.
#   - `lxc-manager.sh`: The script being tested.
#   - `jq`: For parsing the LXC configuration file.
#   - `pct`: The Proxmox command-line tool for container management.
#
# Inputs:
#   - None. The script uses a hardcoded test container ID (9999).
#
# Outputs:
#   - Exits with status 0 if all CRUD tests pass.
#   - Exits with a non-zero status if any test fails, with detailed error
#     messages logged to the console.
#
# ==============================================================================
#

# --- Configuration and Setup ---
set -o pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../../.." &> /dev/null && pwd)

source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"
LXC_MANAGER_SCRIPT="${PHOENIX_BASE_DIR}/bin/managers/lxc-manager.sh"

# --- Test Variables ---
TEST_CTID="9999"
TEMP_TEST_CONFIG_FILE="/tmp/test_lxc_config_crud.json"

# --- Test Functions ---

# Test case 1: Verify container creation
test_create_container() {
    log_info "Running test: Create Container"
    # Ensure the container does not exist before creation
    pct status "$TEST_CTID" &>/dev/null && pct destroy "$TEST_CTID" --force --purge

    # Create a temporary config file for the test container
    jq -n --arg ctid "$TEST_CTID" \
      '{lxc_configs: {($ctid): {name: "test-container", template: "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.gz", storage_pool: "local-zfs", storage_size_gb: 8, memory_mb: 512, cores: 1, network_config: {name: "eth0", bridge: "vmbr0", ip: "dhcp", gw: ""}, unprivileged: true}}}' \
      > "$TEMP_TEST_CONFIG_FILE"

    if ! "$LXC_MANAGER_SCRIPT" "create" "$TEST_CTID" --config "$TEMP_TEST_CONFIG_FILE"; then
        log_error "FAIL: lxc-manager.sh create failed"
        return 1
    fi
    
    if ! pct status "$TEST_CTID" &>/dev/null; then
        log_error "FAIL: Container $TEST_CTID was not created"
        return 1
    fi
    
    log_info "PASS: Create Container"
    return 0
}

# Test case 2: Verify container start
test_start_container() {
    log_info "Running test: Start Container"
    if ! "$LXC_MANAGER_SCRIPT" "start" "$TEST_CTID" --config "$TEMP_TEST_CONFIG_FILE"; then
        log_error "FAIL: lxc-manager.sh start failed"
        return 1
    fi
    
    if ! pct status "$TEST_CTID" | grep -q "status: running"; then
        log_error "FAIL: Container $TEST_CTID is not running"
        return 1
    fi
    
    log_info "PASS: Start Container"
    return 0
}

# Test case 3: Verify container stop
test_stop_container() {
    log_info "Running test: Stop Container"
    if ! "$LXC_MANAGER_SCRIPT" "stop" "$TEST_CTID" --config "$TEMP_TEST_CONFIG_FILE"; then
        log_error "FAIL: lxc-manager.sh stop failed"
        return 1
    fi
    
    if ! pct status "$TEST_CTID" | grep -q "status: stopped"; then
        log_error "FAIL: Container $TEST_CTID is not stopped"
        return 1
    fi
    
    log_info "PASS: Stop Container"
    return 0
}

# Test case 4: Verify container deletion
test_delete_container() {
    log_info "Running test: Delete Container"
    if ! "$LXC_MANAGER_SCRIPT" "delete" "$TEST_CTID" --config "$TEMP_TEST_CONFIG_FILE"; then
        log_error "FAIL: lxc-manager.sh delete failed"
        return 1
    fi
    
    if pct status "$TEST_CTID" &>/dev/null; then
        log_error "FAIL: Container $TEST_CTID was not deleted"
        return 1
    fi
    
    log_info "PASS: Delete Container"
    return 0
}

# --- Main Logic ---
main() {
    local all_tests_passed=true
    
    test_create_container || all_tests_passed=false
    test_start_container || all_tests_passed=false
    test_stop_container || all_tests_passed=false
    test_delete_container || all_tests_passed=false

    # Clean up the temporary config file
    rm -f "$TEMP_TEST_CONFIG_FILE"
    
    if [ "$all_tests_passed" = true ]; then
        log_info "All lxc-manager CRUD tests passed."
        exit 0
    else
        log_error "One or more lxc-manager CRUD tests failed."
        exit 1
    fi
}

# --- Script Execution ---
main "$@"