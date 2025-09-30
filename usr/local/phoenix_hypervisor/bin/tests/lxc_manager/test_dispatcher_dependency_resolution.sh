#!/bin/bash
#
# ==============================================================================
#
# File: test_dispatcher_dependency_resolution.sh
#
# Description:
#   This script is designed to test the dependency resolution logic of the
#   dispatcher component in the `phoenix_orchestrator.sh`. It creates a
#   temporary, in-memory configuration with a chain of dependent containers
#   and then runs the orchestrator in "dry-run" mode. The output of the
#   dry run is then parsed to verify that the container `create` commands are
#   listed in the correct, dependency-aware order.
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
#   - Exits with status 0 if the dependency resolution is correct.
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
TEMP_CONFIG_FILE="/tmp/temp_lxc_configs.json"

# --- Test Functions ---

# Test case: Verify dependency resolution ordering
test_dependency_resolution() {
    log_info "Running test: Dispatcher Dependency Resolution"

    # Create a temporary config file with dependent containers
    cat > "$TEMP_CONFIG_FILE" << EOL
{
    "lxc_configs": {
        "9990": {
            "dependencies": ["9991"]
        },
        "9991": {
            "dependencies": []
        },
        "9992": {
            "dependencies": ["9990"]
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

    # Get the execution plan by calling the dependency resolution function
    local execution_plan
    execution_plan=$(resolve_dependencies 9990 9991 9992)

    # Verify the execution order
    local expected_order="9991 9990 9992"
    # Trim whitespace from the plan
    local actual_order
    actual_order=$(echo "$execution_plan" | xargs)

    if [ "$expected_order" != "$actual_order" ]; then
        log_error "FAIL: Dependency resolution order is incorrect."
        log_error "Expected: $expected_order"
        log_error "Actual:   $actual_order"
        rm "$TEMP_CONFIG_FILE"
        return 1
    fi

    log_info "PASS: Dispatcher Dependency Resolution"
    rm "$TEMP_CONFIG_FILE"
    return 0
}

# --- Main Logic ---
main() {
    if test_dependency_resolution; then
        log_info "Dispatcher dependency resolution test passed."
        exit 0
    else
        log_error "Dispatcher dependency resolution test failed."
        exit 1
    fi
}

# --- Script Execution ---
main "$@"