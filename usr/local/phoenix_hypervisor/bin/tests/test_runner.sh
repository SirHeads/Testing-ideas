#!/bin/bash

# Generic Test Runner Framework
# Description: Provides a simple framework for writing and running test suites.
# This script is intended to be sourced by other test scripts.

# --- State Variables ---
TEST_SUITE_NAME=""
TEST_CASES=()
TEST_RESULTS=()
TESTS_PASSED=0
TESTS_FAILED=0

# --- Core Functions ---

# Initializes a new test suite.
run_test_suite() {
    TEST_SUITE_NAME="$1"
    log_info "Starting Test Suite: $TEST_SUITE_NAME"
    
    # Discover all functions in the calling script that start with "test_case_"
    TEST_CASES=($(compgen -A function test_case_))
    
    for test_case in "${TEST_CASES[@]}"; do
        run_test_case "$test_case"
    done
    
    report_results
}

# Executes a single test case.
run_test_case() {
    local test_case_name="$1"
    log_info "--- Running: $test_case_name ---"
    
    # Run the test case function
    if "$test_case_name"; then
        log_info "--- PASSED: $test_case_name ---"
        TEST_RESULTS+=("PASS: $test_case_name")
        ((TESTS_PASSED++))
    else
        log_error "--- FAILED: $test_case_name ---"
        TEST_RESULTS+=("FAIL: $test_case_name")
        ((TESTS_FAILED++))
    fi
}

# Reports the final results of the test suite.
report_results() {
    log_info "Test Suite Finished: $TEST_SUITE_NAME"
    log_info "----------------------------------------"
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" == "FAIL:"* ]]; then
            log_error "$result"
        else
            log_info "$result"
        fi
    done
    log_info "----------------------------------------"
    log_info "Total Tests: $((${TESTS_PASSED} + ${TESTS_FAILED}))"
    log_info "Passed: ${TESTS_PASSED}"
    log_error "Failed: ${TESTS_FAILED}"
    
    # Exit with a non-zero status if any tests failed
    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
}

# --- Assertion Functions ---

# Asserts that the previous command was successful.
assert_success() {
    local message="$1"
    if [ $? -eq 0 ]; then
        log_info "  [SUCCESS] $message"
        return 0
    else
        log_error "  [FAILURE] $message"
        return 1
    fi
}

# Asserts that two values are equal.
assert_equal() {
    local actual="$1"
    local expected="$2"
    local message="$3"
    
    if [ "$actual" == "$expected" ]; then
        log_info "  [SUCCESS] $message"
        return 0
    else
        log_error "  [FAILURE] $message (Expected: '$expected', Got: '$actual')"
        return 1
    fi
}

# Asserts that a file exists.
assert_file_exists() {
    local file_path="$1"
    local message="$2"
    
    if [ -f "$file_path" ]; then
        log_info "  [SUCCESS] $message"
        return 0
    else
        log_error "  [FAILURE] $message (File not found: $file_path)"
        return 1
    fi
}