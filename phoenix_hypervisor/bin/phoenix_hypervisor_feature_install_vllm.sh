#!/bin/bash
#
# File: feature_install_vllm.sh
# Description: This feature script automates the installation and verification of the vLLM
#              inference server within a Proxmox LXC container. It is designed to be
#              called by the main orchestrator and is fully idempotent.
# Version: 1.0.0
# Author: Roo (AI Engineer)

# --- Source common utilities ---
source "$(dirname "$0")/../bin/phoenix_hypervisor_common_utils.sh"

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
    log_info "Executing vLLM feature for CTID: $CTID"
}

# =====================================================================================
# Function: install_and_test_vllm
# Description: Orchestrates the installation of vLLM and verifies its functionality.
# =====================================================================================
install_and_test_vllm() {
    log_info "Starting vLLM installation and verification in CTID: $CTID"

    # Idempotency Check: See if vllm is already installed
    if pct_exec "$CTID" -- pip3 show vllm &>/dev/null; then
        log_info "vLLM already appears to be installed in CTID $CTID. Skipping installation."
        return 0
    fi

    # Install Python and Pip
    log_info "Installing Python3 and Pip in CTID $CTID..."
    pct_exec "$CTID" -- apt-get update
    pct_exec "$CTID" -- apt-get install -y python3-pip

    # Install vLLM
    log_info "Installing vLLM via pip3 in CTID $CTID..."
    pct_exec "$CTID" -- pip3 install vllm

    # Verification (Optional but recommended)
    # A simple verification could be to check the vllm command's help output.
    # A full test with a model is better but more resource-intensive.
    log_info "Verifying vLLM installation..."
    if ! pct_exec "$CTID" -- python3 -m vllm.entrypoints.api_server --help &>/dev/null; then
        log_fatal "vLLM installation verification failed in CTID $CTID."
    fi

    log_info "vLLM installation and verification complete for CTID $CTID."
}

# =====================================================================================
# Function: main
# Description: Main entry point for the vLLM feature script.
# =====================================================================================
main() {
    parse_arguments "$@"
    install_and_test_vllm
    exit_script 0
}

main "$@"