#!/bin/bash
#
# File: check_nvidia.sh
#
# Description: This health check script is designed to verify the correctness of the
#              NVIDIA driver installation within a specific LXC container. It
#              operates by executing the `nvidia-smi` command inside the container
#              to retrieve the installed driver version and compares it against a
#              target version defined in the container's configuration. This is a
#              critical validation step for GPU-enabled containers.
#
# Dependencies: - A running LXC container with NVIDIA drivers installed.
#               - `phoenix_hypervisor_common_utils.sh` for utility functions.
#               - `jq` for parsing JSON configuration.
#               - `pct` for executing commands within containers.
#
# Inputs:
#   - $1 (CTID): The ID of the LXC container to be checked.
#
# Outputs:
#   - Exits with status 0 if the installed NVIDIA driver version matches the target.
#   - Exits with a non-zero status and logs a fatal error if the CTID is not
#     provided, if `nvidia-smi` fails, or if the driver versions mismatch.
#   - Console output provides detailed logs of the verification process.
#

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling,
# and executing commands within containers.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Main Verification Logic ---
# Encapsulates the main logic of the script.
main() {
    local CTID="$1"
    # Ensure that the container ID is provided as an argument.
    if [ -z "$CTID" ]; then
        log_fatal "Usage: $0 <CTID>"
    fi

    log_info "Starting NVIDIA driver verification in container CTID: $CTID"
    
    # Retrieve the target NVIDIA driver version from the LXC configuration file
    # using the jq_get_value utility function.
    local target_version
    target_version=$(jq_get_value "$CTID" ".nvidia_driver_version")

    # Attempt to get the installed driver version from the container using nvidia-smi.
    # This is performed in a retry loop to handle cases where the container might
    # still be initializing.
    local installed_version
    for i in {1..3}; do
        local output
        # Execute nvidia-smi inside the container to query the driver version.
        output=$(pct_exec "$CTID" nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits)
        # Extract the last line of output to get the version number.
        installed_version=$(echo "$output" | tail -n 1)
        # If a version is successfully retrieved, exit the loop.
        if [ -n "$installed_version" ]; then
            break
        fi
        log_warn "Attempt $i: nvidia-smi failed or returned no version. This can happen if the container is still starting. Retrying in 5 seconds..."
        sleep 5
    done

    # If the installed version could not be determined after retries, fail the check.
    if [ -z "$installed_version" ]; then
        log_fatal "NVIDIA verification failed. Could not retrieve the installed driver version via nvidia-smi after multiple attempts."
    fi

    log_info "Installed NVIDIA driver version found: $installed_version"
    log_info "Target NVIDIA driver version from config: $target_version"

    # Compare the installed version with the target version.
    if [[ "$installed_version" == "$target_version" ]]; then
        log_info "Success: NVIDIA driver version matches the target. Verification successful."
        return 0
    else
        # If the versions do not match, log a fatal error. This indicates a
        # potential misconfiguration or installation issue.
        log_fatal "NVIDIA driver version mismatch! Expected '$target_version', but found '$installed_version'."
    fi
}

# --- Script Execution ---
# Pass all script arguments to the main function.
main "$@"