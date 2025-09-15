#!/bin/bash

# ==============================================================================
# Phoenix Hypervisor Test Suite (Enhanced)
#
# Description:
#   This script runs a comprehensive suite of verification tests to ensure the
#   Phoenix Hypervisor is correctly configured and operational. It provides
#   modular tests, clear pass/fail reporting, and a final summary.
#
# ==============================================================================

# --- Configuration and Setup ---
set -o pipefail
# Sourcing common utilities
# source "$(dirname "$0")/../phoenix_hypervisor_common_utils.sh"

# --- User-configurable variables ---
# These should be configured before running the script, possibly sourced from a config file.
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="password"
SERVER_IP="192.168.1.100"
EXPECTED_TIMEZONE="America/New_York"
PRIMARY_INTERFACE="eth0"
NVME_DEVICE="/dev/nvme0"

# --- Color Codes ---
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

report_pass() {
    local test_name="$1"
    echo -e "${COLOR_GREEN}[ PASS ]${COLOR_RESET} ${test_name}"
    ((PASSED_COUNT++))
    ((TOTAL_TESTS++))
}

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

verify_nvidia_driver() {
    if nvidia-smi | grep -q "Driver Version:"; then
        report_pass "NVIDIA Driver Verification"
    else
        report_fail "NVIDIA Driver Verification" "nvidia-smi command failed or did not return expected output."
    fi
}

verify_zfs_pool_status() {
    if zpool status | grep -q "state: ONLINE" && ! zpool status | grep -q "errors: No known data errors"; then
        report_pass "ZFS Pool Status"
    else
        report_fail "ZFS Pool Status" "ZFS pools are not healthy. Check 'zpool status'."
    fi
}

verify_proxmox_services() {
    local services=("pveproxy" "pvedaemon" "pvestatd")
    local all_active=true
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            all_active=false
            report_fail "Proxmox Service: ${service}" "Service is not active."
        fi
    done
    if [ "$all_active" = true ]; then
        report_pass "Proxmox Services Verification"
    fi
}

verify_system_timezone() {
    if timedatectl | grep -q "Time zone: ${EXPECTED_TIMEZONE}"; then
        report_pass "System Timezone Verification"
    else
        report_fail "System Timezone Verification" "Timezone is not set to ${EXPECTED_TIMEZONE}."
    fi
}

verify_admin_user() {
    if id "${ADMIN_USERNAME}" &>/dev/null; then
        report_pass "Admin User Existence"
    else
        report_fail "Admin User Existence" "Admin user '${ADMIN_USERNAME}' does not exist."
    fi
}

verify_sudo_access() {
    if sudo -l -U "${ADMIN_USERNAME}" | grep -q "(ALL : ALL) ALL"; then
        report_pass "Sudo Access Verification"
    else
        report_fail "Sudo Access Verification" "Admin user '${ADMIN_USERNAME}' does not have expected sudo privileges."
    fi
}

# ==============================================================================
# Test Implementation: Network Services
# ==============================================================================

verify_network_configuration() {
    if ip a show "${PRIMARY_INTERFACE}" | grep -q "inet ${SERVER_IP}"; then
        report_pass "Network Configuration (Static IP)"
    else
        report_fail "Network Configuration (Static IP)" "Interface ${PRIMARY_INTERFACE} does not have IP ${SERVER_IP}."
    fi
}

verify_firewall_status() {
    if sudo ufw status | grep -q "Status: active"; then
        report_pass "Firewall Status (UFW)"
    else
        report_fail "Firewall Status (UFW)" "UFW is not active."
    fi
}

verify_nfs_exports() {
    if showmount -e localhost &>/dev/null; then
        report_pass "NFS Exports Verification"
    else
        report_fail "NFS Exports Verification" "'showmount -e localhost' failed. Check NFS server."
    fi
}

verify_samba_access() {
    if smbclient -L //localhost -U "${ADMIN_USERNAME}%${ADMIN_PASSWORD}" &>/dev/null; then
        report_pass "Samba Access Verification"
    else
        report_fail "Samba Access Verification" "Failed to list Samba shares for user '${ADMIN_USERNAME}'."
    fi
}

# ==============================================================================
# Test Implementation: Hardware and Storage Verification
# ==============================================================================

verify_proxmox_zfs_storage() {
    if pvesm status | grep '^zfs-' | grep -q "active 1"; then
        report_pass "Proxmox ZFS Storage Status"
    else
        report_fail "Proxmox ZFS Storage Status" "No active ZFS storage pools found in Proxmox."
    fi
}

verify_proxmox_nfs_storage() {
    if pvesm status | grep '^nfs-' | grep -q "active 1"; then
        report_pass "Proxmox NFS Storage Status"
    else
        report_fail "Proxmox NFS Storage Status" "No active NFS storage found in Proxmox."
    fi
}

verify_nvme_wear_level() {
    if [ ! -e "${NVME_DEVICE}" ]; then
        report_fail "NVMe Wear Level" "Device ${NVME_DEVICE} not found."
        return
    fi
    local wear_level
    wear_level=$(smartctl -a "${NVME_DEVICE}" | grep "Percentage Used" | awk '{print $3}' | tr -d '%')
    if (( wear_level < 90 )); then
        report_pass "NVMe Wear Level (${wear_level}%)"
    else
        report_fail "NVMe Wear Level" "Wear level is high: ${wear_level}%."
    fi
}

# ==============================================================================
# Test Runner
# ==============================================================================

run_tests() {
    echo -e "${COLOR_BLUE}--- Running Critical System Checks ---${COLOR_RESET}"
    verify_nvidia_driver
    verify_zfs_pool_status
    verify_proxmox_services
    verify_system_timezone
    verify_admin_user
    verify_sudo_access

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

main() {
    echo "============================================================"
    echo "          Phoenix Hypervisor Verification Tests"
    echo "============================================================"

    run_tests

    echo -e "\n${COLOR_BLUE}--- Test Summary ---${COLOR_RESET}"
    echo "Verification Complete. ${TOTAL_TESTS} tests run."
    echo -e "${COLOR_GREEN}Passed: ${PASSED_COUNT}${COLOR_RESET}"
    echo -e "${COLOR_RED}Failed: ${FAILED_COUNT}${COLOR_RESET}"
    echo "============================================================"

    if (( FAILED_COUNT > 0 )); then
        exit 1
    fi
    exit 0
}

main
