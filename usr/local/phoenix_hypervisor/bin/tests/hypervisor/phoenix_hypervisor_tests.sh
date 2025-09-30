#!/bin/bash

# ==============================================================================
#
# File: phoenix_hypervisor_tests.sh
#
# Description:
#   This script is a comprehensive test suite for validating the configuration
#   and operational status of the Phoenix Hypervisor host. It is designed to be
#   run directly on the Proxmox server to check critical components such as
#   NVIDIA drivers, ZFS pools, Proxmox services, networking, and storage.
#   The script is structured into modular, single-purpose test functions and
#   provides a clear, color-coded summary of the results.
#
# Dependencies:
#   - `phoenix_hypervisor_common_utils.sh` for utility functions.
#   - Standard system commands: `nvidia-smi`, `zpool`, `systemctl`, `timedatectl`,
#     `ip`, `ufw`, `showmount`, `smbclient`, `pvesm`, `smartctl`.
#
# Inputs:
#   - User-configurable variables at the top of the script (e.g., ADMIN_USERNAME,
#     SERVER_IP) may need to be adjusted to match the specific environment.
#
# Outputs:
#   - Exits with status 0 if all tests pass.
#   - Exits with status 1 if one or more tests fail.
#   - Provides a detailed, color-coded report of each test's pass/fail status
#     and a final summary to the console.
#
# ==============================================================================

# --- Configuration and Setup ---
set -o pipefail
# Sourcing common utilities for functions like is_command_available.
source "$(dirname "$0")/../phoenix_hypervisor_common_utils.sh"

# --- User-Configurable Variables ---
# These variables should be customized to match the target hypervisor environment.
# For a production system, these should be sourced from a secure configuration file.
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="password" # Note: Hardcoding passwords is not recommended for production.
SERVER_IP="192.168.1.100"
EXPECTED_TIMEZONE="America/New_York"
PRIMARY_INTERFACE="eth0"
NVME_DEVICE="/dev/nvme0"

# --- Color Codes for Output Formatting ---
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# --- Test Counters ---
PASSED_COUNT=0
FAILED_COUNT=0
TOTAL_TESTS=0

# ==============================================================================
# Test Reporting Functions
# ==============================================================================

#
# Function: report_pass
# Description: Prints a formatted success message and increments pass counters.
# Arguments: $1 - The name of the test that passed.
#
report_pass() {
    local test_name="$1"
    echo -e "${COLOR_GREEN}[ PASS ]${COLOR_RESET} ${test_name}"
    ((PASSED_COUNT++))
    ((TOTAL_TESTS++))
}

#
# Function: report_fail
# Description: Prints a formatted failure message and increments fail counters.
# Arguments: $1 - The name of the test that failed.
#            $2 - A message describing the reason for failure.
#
report_fail() {
    local test_name="$1"
    local message="$2"
    echo -e "${COLOR_RED}[ FAIL ]${COLOR_RESET} ${test_name}: ${message}"
    ((FAILED_COUNT++))
    ((TOTAL_TESTS++))
}

# ==============================================================================
# Test Implementation: Critical System Checks
# ==============================================================================

# Verifies that the NVIDIA drivers are loaded and `nvidia-smi` is functional.
verify_nvidia_driver() {
    if nvidia-smi | grep -q "Driver Version:"; then
        report_pass "NVIDIA Driver Verification"
    else
        report_fail "NVIDIA Driver Verification" "`nvidia-smi` command failed or did not return expected output."
    fi
}

# Checks the health of all ZFS pools on the system.
verify_zfs_pool_status() {
    # Note: The original logic was flawed. A healthy pool has "No known data errors".
    if zpool status | grep -q "state: ONLINE" && zpool status | grep -q "errors: No known data errors"; then
        report_pass "ZFS Pool Status"
    else
        report_fail "ZFS Pool Status" "ZFS pools are not healthy. Check `zpool status` for details."
    fi
}

# Ensures that essential Proxmox services are active.
verify_proxmox_services() {
    local services=("pveproxy" "pvedaemon" "pvestatd")
    local all_active=true
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            all_active=false
            # This reports individual service failures.
            report_fail "Proxmox Service Check" "Service '${service}' is not active."
        fi
    done
    if [ "$all_active" = true ]; then
        report_pass "Proxmox Services Verification"
    fi
}

# Validates that the system timezone is set to the expected value.
verify_system_timezone() {
    if timedatectl | grep -q "Time zone: ${EXPECTED_TIMEZONE}"; then
        report_pass "System Timezone Verification"
    else
        report_fail "System Timezone Verification" "Timezone is not set to the expected '${EXPECTED_TIMEZONE}'."
    fi
}

# Checks if the primary administrative user exists.
verify_admin_user() {
    if id "${ADMIN_USERNAME}" &>/dev/null; then
        report_pass "Admin User Existence"
    else
        report_fail "Admin User Existence" "Admin user '${ADMIN_USERNAME}' does not exist."
    fi
}

# Verifies that the admin user has passwordless sudo privileges.
verify_sudo_access() {
    if sudo -l -U "${ADMIN_USERNAME}" | grep -q "(ALL : ALL) ALL"; then
        report_pass "Sudo Access Verification"
    else
        report_fail "Sudo Access Verification" "Admin user '${ADMIN_USERNAME}' does not have expected sudo privileges."
    fi
}

# ==============================================================================
# Test Implementation: Utility Functions (Self-Test)
# ==============================================================================

# This function tests the `is_command_available` utility function itself.
verify_is_command_available() {
    # Test for a command that should exist.
    if is_command_available "ls"; then
        report_pass "Utility Self-Test: is_command_available (positive case)"
    else
        report_fail "Utility Self-Test: is_command_available (positive case)" "is_command_available could not find the 'ls' command."
    fi

    # Test for a command that should not exist.
    if ! is_command_available "nonexistentcommand12345"; then
        report_pass "Utility Self-Test: is_command_available (negative case)"
    else
        report_fail "Utility Self-Test: is_command_available (negative case)" "is_command_available wrongfully found 'nonexistentcommand12345'."
    fi
}
# ==============================================================================
# Test Implementation: Network Services
# ==============================================================================

# Checks if the primary network interface has the correct static IP address.
verify_network_configuration() {
    if ip a show "${PRIMARY_INTERFACE}" | grep -q "inet ${SERVER_IP}"; then
        report_pass "Network Configuration (Static IP)"
    else
        report_fail "Network Configuration (Static IP)" "Interface ${PRIMARY_INTERFACE} does not have the expected IP ${SERVER_IP}."
    fi
}

# Verifies that the UFW firewall is active.
verify_firewall_status() {
    if sudo ufw status | grep -q "Status: active"; then
        report_pass "Firewall Status (UFW)"
    else
        report_fail "Firewall Status (UFW)" "UFW is not active."
    fi
}

# Checks if the NFS server is running and exporting shares.
verify_nfs_exports() {
    if showmount -e localhost &>/dev/null; then
        report_pass "NFS Exports Verification"
    else
        report_fail "NFS Exports Verification" "`showmount -e localhost` failed. Check NFS server status."
    fi
}

# Attempts to connect to the local Samba server to verify it's operational.
verify_samba_access() {
    # This test relies on the ADMIN_PASSWORD variable.
    if smbclient -L //localhost -U "${ADMIN_USERNAME}%${ADMIN_PASSWORD}" &>/dev/null; then
        report_pass "Samba Access Verification"
    else
        report_fail "Samba Access Verification" "Failed to list Samba shares for user '${ADMIN_USERNAME}'. Check credentials or Samba service."
    fi
}

# ==============================================================================
# Test Implementation: Hardware and Storage Verification
# ==============================================================================

# Verifies that Proxmox has an active ZFS storage pool configured.
verify_proxmox_zfs_storage() {
    if pvesm status | grep '^zfs-' | grep -q "active 1"; then
        report_pass "Proxmox ZFS Storage Status"
    else
        report_fail "Proxmox ZFS Storage Status" "No active ZFS storage pools found in Proxmox storage manager."
    fi
}

# Verifies that Proxmox has an active NFS storage pool configured.
verify_proxmox_nfs_storage() {
    if pvesm status | grep '^nfs-' | grep -q "active 1"; then
        report_pass "Proxmox NFS Storage Status"
    else
        report_fail "Proxmox NFS Storage Status" "No active NFS storage found in Proxmox storage manager."
    fi
}

# Checks the wear level of the primary NVMe device to prevent failures.
verify_nvme_wear_level() {
    if [ ! -e "${NVME_DEVICE}" ]; then
        report_fail "NVMe Wear Level Check" "Device ${NVME_DEVICE} not found."
        return
    fi
    local wear_level
    # Use smartctl to get the "Percentage Used" attribute.
    wear_level=$(smartctl -a "${NVME_DEVICE}" | grep "Percentage Used" | awk '{print $3}' | tr -d '%')
    if (( wear_level < 90 )); then
        report_pass "NVMe Wear Level Check (${wear_level}%)"
    else
        report_fail "NVMe Wear Level Check" "Wear level is critically high: ${wear_level}%."
    fi
}

# ==============================================================================
# Test Runner
# ==============================================================================

#
# Function: run_tests
# Description: Executes all the defined test functions in logical groups.
#
run_tests() {
    echo -e "${COLOR_BLUE}--- Running Critical System Checks ---${COLOR_RESET}"
    verify_nvidia_driver
    verify_zfs_pool_status
    verify_proxmox_services
    verify_system_timezone
    verify_admin_user
    verify_sudo_access

    echo -e "\n${COLOR_BLUE}--- Running Utility Function Self-Tests ---${COLOR_RESET}"
    verify_is_command_available

    echo -e "\n${COLOR_BLUE}--- Running Network Services Checks ---${COLOR_RESET}"
    verify_network_configuration
    verify_firewall_status
    verify_nfs_exports
    verify_samba_access

    echo -e "\n${COLOR_BLUE}--- Running Hardware and Storage Checks ---${COLOR_RESET}"
    verify_proxmox_zfs_storage
    verify_proxmox_nfs_storage
    verify_nvme_wear_level
}

# ==============================================================================
# Main Execution
# ==============================================================================

#
# Function: main
# Description: The main entry point of the script. It prints a header, runs the
#              tests, and prints a final summary.
#
main() {
    echo "============================================================"
    echo "          Phoenix Hypervisor Verification Test Suite"
    echo "============================================================"

    run_tests

    echo -e "\n${COLOR_BLUE}--- Test Summary ---${COLOR_RESET}"
    echo "Verification Complete. ${TOTAL_TESTS} tests run."
    echo -e "${COLOR_GREEN}Passed: ${PASSED_COUNT}${COLOR_RESET}"
    echo -e "${COLOR_RED}Failed: ${FAILED_COUNT}${COLOR_RESET}"
    echo "============================================================"

    # Exit with a non-zero status code if any tests failed.
    if (( FAILED_COUNT > 0 )); then
        exit 1
    fi
    exit 0
}

# Execute the main function.
main
