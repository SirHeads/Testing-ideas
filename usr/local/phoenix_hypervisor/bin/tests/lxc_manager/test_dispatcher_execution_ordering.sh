#!/bin/bash
#
# ==============================================================================
#
# File: test_dispatcher_execution_ordering.sh
#
# Description:
#   This script is designed to test the execution ordering logic of the
#   dispatcher component in the `phoenix_orchestrator.sh`. It creates a
#   temporary configuration file with specified `execution_order` values for
#   a set of containers. The script then runs the orchestrator in "dry-run"
#   mode and parses the output to verify that the `create` commands are
#   generated in the correct, user-defined sequence.
#
# Dependencies:
#   - `phoenix_hypervisor_common_utils.sh`: For standardized logging.
#   - `phoenix_orchestrator.sh`: The script containing the dispatcher logic.
#   - `jq`: For creating the temporary JSON configuration.
#
# Inputs:
#   - None. The script is self-contained and uses a temporary config file.
#
# Outputs:
#   - Exits with status 0 if the execution order is correct.
#   - Exits with a non-zero status if the test fails, logging the expected
#     and actual execution order.
#
# ==============================================================================
#

# --- Configuration and Setup ---
set -o pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../../.." &> /dev/null && pwd)

source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"
PHOENIX_SCRIPT="${PHOENIX_BASE_DIR}/bin/phoenix"

# --- Test Variables ---
TEMP_CONFIG_FILE="/tmp/temp_lxc_configs_execution_order.json"

# --- Test Functions ---

# Test case: Verify execution ordering
test_execution_ordering() {
    log_info "Running test: Dispatcher Execution Ordering"

    # Create a temporary config file with specified execution orders
    cat > "$TEMP_CONFIG_FILE" << EOL
{
    "lxc_configs": {
        "9980": {
            "execution_order": 2
        },
        "9981": {
            "execution_order": 1
        },
        "9982": {
            "execution_order": 3
        }
    }
}
EOL

    # Run the orchestrator in dry-run mode to get the execution plan
    local execution_plan
    # Source the phoenix script to get access to its functions
    source "$PHOENIX_SCRIPT"

    # Override the get_config_value function to point to our temporary config
    get_config_value() {
        if [[ "$1" == ".core_paths.lxc_config_file" ]]; then
            echo "$TEMP_CONFIG_FILE"
        else
            # Call the original function if it exists, otherwise return empty
            type -t get_config_value_orig &>/dev/null && get_config_value_orig "$1" || echo ""
        fi
    }

    # We need to move the original function to avoid recursion
    eval "$(declare -f get_config_value | sed 's/get_config_value/get_config_value_orig/')"

    # Get the execution plan by calling the sort function
    local execution_plan
    execution_plan=$(sort_by_boot_order 9980 9981 9982)

    # Verify the execution order
    local expected_order="9981 9980 9982"
    # Trim whitespace from the plan
    local actual_order
    actual_order=$(echo "$execution_plan" | xargs)

    if [ "$expected_order" != "$actual_order" ]; then
        log_error "FAIL: Execution order is incorrect."
        log_error "Expected: $expected_order"
        log_error "Actual:   $actual_order"
        rm "$TEMP_CONFIG_FILE"
        return 1
    fi

    log_info "PASS: Dispatcher Execution Ordering"
    rm "$TEMP_CONFIG_FILE"
    return 0
}

# --- Main Logic ---
main() {
    if test_execution_ordering; then
        log_info "Dispatcher execution ordering test passed."
        exit 0
    else
        log_error "Dispatcher execution ordering test failed."
        exit 1
    fi
}

# --- Script Execution ---
main "$@"