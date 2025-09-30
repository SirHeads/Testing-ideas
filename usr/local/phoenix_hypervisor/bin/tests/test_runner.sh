#!/bin/bash
#
# File: test_runner.sh
#
# Description: This script is a generic test runner designed to execute a suite of
#              tests within a specified LXC container. It reads the test suite
#              definitions from the `phoenix_lxc_configs.json` file, copies the
#              necessary test scripts into the container, executes them, and reports
#              the results. This allows for flexible, configuration-driven testing
#              of container functionality.
#
# Dependencies: - `phoenix_hypervisor_common_utils.sh` for logging and utilities.
#               - `jq` for parsing the JSON configuration.
#               - `pct` for interacting with LXC containers.
#
# Inputs:
#   - $1 (CTID): The ID of the LXC container in which to run the tests.
#   - $2 (SUITE_NAME): The name of the test suite to execute, as defined in the
#     `phoenix_lxc_configs.json` file (e.g., "health_checks", "integration_tests").
#
# Outputs:
#   - Exits with status 0 if all tests in the suite pass.
#   - Exits with status 1 if any test fails or if there is a configuration error.
#   - Console output provides detailed logs of the test execution and results.
#

# --- Configuration and Setup ---
set -o pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Script Variables ---
CTID="$1"
SUITE_NAME="$2"

# Source shared utilities and define key file paths.
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"
LXC_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_lxc_configs.json"
# Define a temporary directory inside the container for test artifacts.
TEMP_DIR_IN_CONTAINER="/tmp/phoenix_tests"

# --- Main Logic ---
main() {
    # 1. Argument Validation: Ensure both CTID and suite name are provided.
    if [ -z "$CTID" ] || [ -z "$SUITE_NAME" ]; then
        log_error "Usage: $0 <CTID> <test_suite_name>"
        exit 1
    fi

    log_info "Starting test suite '$SUITE_NAME' for container CTID: $CTID"

    # 2. Container Status Check: Ensure the target container is running.
    if ! pct status "$CTID" >/dev/null 2>&1; then
        log_warn "Container $CTID is not running. Attempting to start it..."
        pct start "$CTID"
        sleep 5 # Wait a moment for the container to initialize.
    fi

    # 3. Test Discovery: Use jq to parse the config file and find the tests for the specified suite.
    # The tests are encoded in Base64 to handle potential special characters in JSON.
    local tests
    tests=$(jq -r --arg ctid "$CTID" --arg suite_name "$SUITE_NAME" '.lxc_configs[$ctid].tests[$suite_name] // [] | .[] | @base64' "$LXC_CONFIG_FILE")

    if [ -z "$tests" ]; then
        log_warn "No tests found for suite '$SUITE_NAME' in CTID $CTID's configuration. Exiting as successful."
        exit 0
    fi

    # 4. Test Execution Loop
    local overall_suite_status=0
    for test_b64 in $tests; do
        # Decode the test definition from Base64.
        local test_json
        test_json=$(echo "$test_b64" | base64 --decode)
        
        # Extract test details.
        local test_name
        test_name=$(echo "$test_json" | jq -r '.name')
        local test_type
        test_type=$(echo "$test_json" | jq -r '.type')
        local test_path
        test_path=$(echo "$test_json" | jq -r '.path')
        local test_script_path="${SCRIPT_DIR}/${test_path}"

        log_info "--- Executing test: '$test_name' ---"

        # Currently, only 'script' type is supported.
        if [ "$test_type" != "script" ]; then
            log_error "Test type '$test_type' is not supported by this runner."
            overall_suite_status=1
            continue
        fi

        # Verify the test script file exists on the host.
        if [ ! -f "$test_script_path" ]; then
            log_error "Test script not found at host path: $test_script_path."
            overall_suite_status=1
            continue
        fi

        # Prepare the container: create a temp directory, push the script, and make it executable.
        pct exec "$CTID" -- mkdir -p "$TEMP_DIR_IN_CONTAINER"
        local script_in_container="${TEMP_DIR_IN_CONTAINER}/$(basename "$test_script_path")"
        pct push "$CTID" "$test_script_path" "$script_in_container"
        pct exec "$CTID" -- chmod +x "$script_in_container"

        # Execute the script inside the container and capture its output and exit code.
        local output
        if output=$(pct exec "$CTID" -- "$script_in_container" 2>&1); then
            log_info "  [ PASS ] $test_name"
        else
            log_error "  [ FAIL ] $test_name"
            log_error "    Test script output:"
            # Log the captured output line by line for clarity.
            while IFS= read -r line; do
                log_error "      $line"
            done <<< "$output"
            overall_suite_status=1
        fi

        # Clean up the temporary directory in the container after the test.
        pct exec "$CTID" -- rm -rf "$TEMP_DIR_IN_CONTAINER"
    done

    # 5. Exit with the overall status of the suite.
    exit "$overall_suite_status"
}

# --- Script Execution ---
main "$@"