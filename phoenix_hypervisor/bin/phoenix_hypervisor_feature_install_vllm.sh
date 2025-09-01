#!/bin/bash
#
# File: feature_install_vllm.sh
# Description: This feature script automates the installation and verification of the vLLM
#              inference server within a Proxmox LXC container. It is designed to be
#              called by the main orchestrator and is fully idempotent.
# Version: 1.0.0
# Author: Roo (AI Engineer)

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

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
    log_info "Executing vLLM feature for CTID: $CTID"
}

# =====================================================================================
# Function: install_and_test_vllm
# Description: Orchestrates the installation of vLLM and verifies its functionality.
# =====================================================================================
install_and_test_vllm() {
    log_info "Starting vLLM installation and verification in CTID: $CTID"

    log_info "Verifying NVIDIA GPU access in CTID $CTID..."
    if ! pct_exec "$CTID" nvidia-smi; then
        log_fatal "NVIDIA GPU not accessible in CTID $CTID. Aborting vLLM installation."
    fi
    log_info "NVIDIA GPU access verified."
    local vllm_dir="/opt/vllm"

    # Idempotency Check: See if the vLLM directory and virtual environment exist
    if pct_exec "$CTID" [ -d "$vllm_dir" ] && pct_exec "$CTID" [ -f "${vllm_dir}/Pipfile" ]; then
        log_info "vLLM environment already exists in CTID $CTID. Skipping installation."
        return 0
    fi

    # Install Python, Pip, Pipenv, and build tools
    log_info "Installing Python3, Pip, Pipenv, and build tools in CTID $CTID..."
    pct_exec "$CTID" apt-get update
    pct_exec "$CTID" apt-get install -y software-properties-common
    pct_exec "$CTID" add-apt-repository -y ppa:deadsnakes/ppa
    pct_exec "$CTID" apt-get update
    pct_exec "$CTID" apt-get install -y python3.11-full python3.11-dev python3.11-venv python3-pip pipenv build-essential cmake

    # Create vLLM directory and Pipfile
    log_info "Creating vLLM environment in CTID $CTID..."
    pct_exec "$CTID" mkdir -p "$vllm_dir"
    pct_exec "$CTID" bash -c "cat <<'EOF' > ${vllm_dir}/Pipfile
[[source]]
url = \"https://pypi.org/simple\"
verify_ssl = true
name = \"pypi\"

[[source]]
url = \"https://download.pytorch.org/whl/cu128\"
verify_ssl = true
name = \"pytorch\"

[[source]]
url = \"https://wheels.vllm.ai\"
verify_ssl = true
name = \"vllm\"

[packages]
torch = \"==2.2.2\"
vllm = \"==0.4.1\"
flash-attn = \"*\"
transformers = \"*\"
flashinfer-python = {version = \"*\", index = \"vllm\"}

[requires]
python_version = \"3.11\"
EOF"

    # --- Two-Stage Package Installation ---
    log_info "Installing PyTorch and build dependencies in CTID $CTID..."
    pct_exec "$CTID" bash -c "cd $vllm_dir && pipenv run pip install torch==2.2.2 setuptools wheel ninja packaging --index-url https://pypi.org/simple --extra-index-url https://download.pytorch.org/whl/cu128"

    log_info "Installing vLLM and related packages in CTID $CTID..."
    pct_exec "$CTID" bash -c "cd $vllm_dir && pipenv run pip install vllm==0.4.1 'flash-attn' transformers --no-build-isolation --index-url https://pypi.org/simple --extra-index-url https://download.pytorch.org/whl/cu128"
    pct_exec "$CTID" bash -c "cd $vllm_dir && pipenv run pip install flashinfer-python --index-url https://wheels.vllm.ai --extra-index-url https://pypi.org/simple"

    # Verification
    log_info "Verifying vLLM installation..."
    if ! pct_exec "$CTID" bash -c "cd $vllm_dir && pipenv run python -m vllm.entrypoints.api_server --help" &>/dev/null; then
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