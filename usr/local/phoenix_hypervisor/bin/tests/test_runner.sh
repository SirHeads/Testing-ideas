#!/bin/bash
#
# File: test_runner.sh
# Description: Executes a defined test suite for a given container.
#
# Arguments:
#   $1 - CTID of the container to test.
#   $2 - Name of the test suite to execute (e.g., health_checks).

# --- Configuration and Setup ---
set -o pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Script Variables ---
CTID="$1"
SUITE_NAME="$2"

source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"
LXC_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_lxc_configs.json"
TEMP_DIR_IN_CONTAINER="/tmp/phoenix_tests"

# --- Main Logic ---
main() {
    if [ -z "$CTID" ] || [ -z "$SUITE_NAME" ]; then
        log_error "Usage: $0 <CTID> <test_suite>"
        exit 1
    fi

    log_info "Running test suite '$SUITE_NAME' for CTID: $CTID"

    if ! pct status "$CTID" >/dev/null 2>&1; then
        log_warn "Container $CTID is not running. Attempting to start it..."
        pct start "$CTID"
        sleep 5
    fi

    local tests=$(jq -r --arg ctid "$CTID" --arg suite_name "$SUITE_NAME" '.lxc_configs[$ctid].tests[$suite_name] // [] | .[] | @base64' "$LXC_CONFIG_FILE")

    if [ -z "$tests" ]; then
        log_warn "No tests found for suite '$SUITE_NAME' in CTID $CTID."
        exit 0
    fi

    local overall_suite_status=0
    for test_b64 in $tests; do
        local test_json=$(echo "$test_b64" | base64 --decode)
        local test_name=$(echo "$test_json" | jq -r '.name')
        local test_type=$(echo "$test_json" | jq -r '.type')
        local test_path=$(echo "$test_json" | jq -r '.path')
        local test_script_path="${SCRIPT_DIR}/${test_path}"

        log_info "Executing test: '$test_name'"

        if [ "$test_type" != "script" ]; then
            log_error "Test type '$test_type' not supported."
            overall_suite_status=1
            continue
        fi

        if [ ! -f "$test_script_path" ]; then
            log_error "Test script not found at $test_script_path."
            overall_suite_status=1
            continue
        fi

        pct exec "$CTID" -- mkdir -p "$TEMP_DIR_IN_CONTAINER"
        local script_in_container="${TEMP_DIR_IN_CONTAINER}/$(basename "$test_script_path")"
        pct push "$CTID" "$test_script_path" "$script_in_container"
        pct exec "$CTID" -- chmod +x "$script_in_container"

        local output
        if output=$(pct exec "$CTID" -- "$script_in_container" 2>&1); then
            log_info "  [ PASS ] $test_name"
        else
            log_error "  [ FAIL ] $test_name"
            log_error "    Output:"
            while IFS= read -r line; do
                log_error "      $line"
            done <<< "$output"
            overall_suite_status=1
        fi

        pct exec "$CTID" -- rm -rf "$TEMP_DIR_IN_CONTAINER"
    done

    exit "$overall_suite_status"
}

main "$@"