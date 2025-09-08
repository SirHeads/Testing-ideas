#!/bin/bash

# ==============================================================================
# Phoenix Hypervisor Test Suite
#
# Description:
#   This script runs a series of verification tests for the Phoenix Hypervisor.
#   It is designed to be robust and provide clear, actionable feedback without
#   halting on individual test failures.
#
# ==============================================================================

# --- Configuration and Setup ---
set -o pipefail

# --- Color Codes ---
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# --- Test Counters ---
PASSED_COUNT=0
FAILED_COUNT=0
WARNING_COUNT=0
TOTAL_TESTS=0

# ==============================================================================
# Test Reporting Functions
# ==============================================================================

# --- report_result ---
# Prints a formatted test result to the console.
#
# @param $1: Test name
# @param $2: Result type (PASS, FAIL, WARN)
# @param $3: Detailed message
#
report_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    local color

    case "$result" in
        PASS)
            color="$COLOR_GREEN"
            ((PASSED_COUNT++))
            ;;
        FAIL)
            color="$COLOR_RED"
            ((FAILED_COUNT++))
            ;;
        WARN)
            color="$COLOR_YELLOW"
            ((WARNING_COUNT++))
            ;;
        *)
            color="$COLOR_RESET"
            ;;
    esac

    echo -e "${color}[ ${result} ]${COLOR_RESET} ${test_name}: ${message}"
    ((TOTAL_TESTS++))
}

# ==============================================================================
# Test Suite
# ==============================================================================

# --- run_test ---
# Executes a single test and reports its result.
#
# @param $1: Test function name
#
run_test() {
    local test_function="$1"
    echo -e "\n${COLOR_BLUE}--- Running Test: ${test_function} ---${COLOR_RESET}"
    eval "$test_function"
}

# --- Test 1: Automatic Pass ---
test_automatic_pass() {
    report_result "Automatic Pass" "PASS" "This test is designed to always pass."
}

# --- Test 2: Automatic Fail ---
test_automatic_fail() {
    report_result "Automatic Fail" "FAIL" "This test is designed to always fail."
}

# --- Test 3: Unexpected Result ---
test_unexpected_result() {
    report_result "Unexpected Result" "WARN" "This test simulates an unexpected or null result."
}

# --- Test 4: NVIDIA SMI Check ---
test_nvidia_smi() {
    if ! command -v nvidia-smi &> /dev/null; then
        report_result "NVIDIA SMI" "FAIL" "nvidia-smi command not found in PATH."
        return
    fi

    local smi_output
    smi_output=$(nvidia-smi 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        report_result "NVIDIA SMI" "FAIL" "Command failed with exit code ${exit_code}. Output: ${smi_output}"
        return
    fi

    # The command succeeded, now check the output for signs of a GPU
    if echo "${smi_output}" | grep -q "Driver Version:"; then
        report_result "NVIDIA SMI" "PASS" "nvidia-smi command is available and found a GPU."
    else
        report_result "NVIDIA SMI" "FAIL" "Command ran, but output did not contain expected 'Driver Version:' string. Output: ${smi_output}"
    fi
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    echo "============================================================"
    echo "          Phoenix Hypervisor Verification Tests"
    echo "============================================================"

    # --- Run all tests ---
    run_test test_automatic_pass
    run_test test_automatic_fail
    run_test test_unexpected_result
    run_test test_nvidia_smi

    # --- Print Summary ---
    echo -e "\n${COLOR_BLUE}--- Test Summary ---${COLOR_RESET}"
    echo -e "Total Tests: ${TOTAL_TESTS}"
    echo -e "${COLOR_GREEN}Passed: ${PASSED_COUNT}${COLOR_RESET}"
    echo -e "${COLOR_RED}Failed: ${FAILED_COUNT}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Warnings: ${WARNING_COUNT}${COLOR_RESET}"
    echo "============================================================"

    # Exit with a non-zero status if any tests failed
    if (( FAILED_COUNT > 0 )); then
        exit 1
    fi
    exit 0
}

# --- Run main ---
main
