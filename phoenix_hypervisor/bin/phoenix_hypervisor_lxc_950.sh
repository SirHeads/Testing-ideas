#!/bin/bash
#
# File: phoenix_hypervisor_lxc_950.sh
# Description: Application runner for the vllmQwen3Coder service (CTID 950).
#              This script is called by the main orchestrator to launch the persistent
#              vLLM server after all feature installations are complete.
# Version: 2.0.0
# Author: Roo (AI Engineer)

# --- Source common utilities ---
source "$(dirname "$0")/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""

# =====================================================================================
# Function: parse_arguments
# Description: Parses the CTID from command-line arguments.
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Executing application runner for CTID: $CTID"
}

# =====================================================================================
# Function: launch_vllm_server
# Description: Launches the vLLM server as a persistent background service.
# =====================================================================================
launch_vllm_server() {
    log_info "Launching vLLM Qwen3 Coder server in CTID: $CTID"

    # Idempotency Check: See if the server is already running
    if pct_exec "$CTID" -- pgrep -f "vllm.entrypoints.api_server" &>/dev/null; then
        log_info "vLLM server process is already running in CTID $CTID. Skipping launch."
        return 0
    fi

    local vllm_model
    vllm_model=$(jq_get_value "$CTID" ".vllm_model")
    local tensor_parallel_size
    tensor_parallel_size=$(jq_get_value "$CTID" ".vllm_tensor_parallel_size")
    local vllm_log_file="/var/log/vllm_server.log"

    local serve_cmd="python3 -m vllm.entrypoints.api_server --host 0.0.0.0 --model \"$vllm_model\" --tensor-parallel-size $tensor_parallel_size"
    local full_launch_cmd="nohup $serve_cmd > $vllm_log_file 2>&1 &"

    log_info "Executing launch command: $full_launch_cmd"
    if ! pct_exec "$CTID" -- bash -c "$full_launch_cmd"; then
        log_fatal "vLLM server launch failed for CTID $CTID."
    fi

    # Wait a few seconds to ensure the process has time to start before we verify
    sleep 10
    
    if ! pct_exec "$CTID" -- pgrep -f "vllm.entrypoints.api_server" &>/dev/null; then
        log_fatal "vLLM server process did not start successfully. Check logs at $vllm_log_file inside the container."
    fi

    log_info "vLLM Qwen3 Coder server launched successfully in CTID $CTID."
}

# =====================================================================================
# Function: main
# Description: Main entry point for the application runner script.
# =====================================================================================
main() {
    parse_arguments "$@"
    launch_vllm_server
    exit_script 0
}

main "$@"