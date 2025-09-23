#!/bin/bash
#
# File: check_nvidia.sh
# Description: Health check script to verify the NVIDIA driver installation
#              inside a container by running nvidia-smi.

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Main Verification Logic ---
main() {
    local CTID="$1"
    if [ -z "$CTID" ]; then
        log_fatal "Usage: $0 <CTID>"
    fi

    log_info "Verifying NVIDIA installation in CTID: $CTID"
    local target_version
    target_version=$(jq_get_value "$CTID" ".nvidia_driver_version")

    local installed_version
    for i in {1..3}; do
        local output
        output=$(pct_exec "$CTID" nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits)
        installed_version=$(echo "$output" | tail -n 1)
        if [ -n "$installed_version" ]; then
            break
        fi
        log_warn "Attempt $i: nvidia-smi failed or returned no version. Retrying in 5 seconds..."
        sleep 5
    done

    if [ -z "$installed_version" ]; then
        log_fatal "NVIDIA verification failed. Could not retrieve installed driver version via nvidia-smi."
    fi

    log_info "Installed NVIDIA driver version: $installed_version"
    log_info "Target NVIDIA driver version:    $target_version"

    if [[ "$installed_version" == "$target_version" ]]; then
        log_info "NVIDIA driver version matches the target. Verification successful."
        return 0
    else
        log_fatal "NVIDIA driver version mismatch! Expected '$target_version', but found '$installed_version'."
    fi
}

main "$@"