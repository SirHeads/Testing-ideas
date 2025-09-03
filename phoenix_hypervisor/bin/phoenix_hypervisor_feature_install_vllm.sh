#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_vllm.sh
# Description: This feature script automates the installation and verification of the vLLM
#              inference server from source within a Proxmox LXC container. It is
#              designed to be called by the main orchestrator and is fully idempotent.
#
# Host System Requirements:
# - NVIDIA Driver Version: 580+
#
# Version: 3.0.0
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
# Description: Orchestrates the installation of vLLM from source and verifies its
#              functionality.
# =====================================================================================
install_and_test_vllm() {
    log_info "Starting vLLM source installation and verification in CTID: $CTID"

    log_info "Verifying NVIDIA GPU access in CTID $CTID..."
    if ! pct_exec "$CTID" nvidia-smi; then
        log_fatal "NVIDIA GPU not accessible in CTID $CTID. Aborting vLLM installation."
    fi
    log_info "NVIDIA GPU access verified."
    local vllm_dir="/opt/vllm"
    local vllm_repo_dir="/opt/vllm_repo"

    # Idempotency Check: Check if vLLM is installed in editable mode.
    if pct_exec "$CTID" "${vllm_dir}/bin/pip" list | grep -q "vllm.*${vllm_repo_dir}"; then
        log_info "vLLM appears to be installed from source in CTID $CTID. Skipping installation."
        return 0
    fi

    # Install Python, build tools, and git
    log_info "Installing Python 3.11, build tools, and git in CTID $CTID..."
    pct_exec "$CTID" apt-get update
    pct_exec "$CTID" apt-get install -y software-properties-common
    pct_exec "$CTID" add-apt-repository -y ppa:deadsnakes/ppa
    pct_exec "$CTID" apt-get update
    pct_exec "$CTID" apt-get install -y python3.11-full python3.11-dev python3.11-venv python3-pip build-essential cmake git

    # Create vLLM virtual environment
    log_info "Creating vLLM virtual environment in ${vllm_dir} for CTID $CTID..."
    pct_exec "$CTID" mkdir -p "$vllm_dir"
    pct_exec "$CTID" python3.11 -m venv "$vllm_dir"

    # Upgrade pip
    log_info "Upgrading pip in the new virtual environment..."
    pct_exec "$CTID" "${vllm_dir}/bin/pip" install --upgrade pip

    # Install PyTorch Nightly
    log_info "Installing PyTorch nightly for CUDA 12.8+..."
    pct_exec "$CTID" "${vllm_dir}/bin/pip" install --pre torch --index-url https://download.pytorch.org/whl/nightly/cu128
    log_info "Cleaning pip cache after PyTorch installation..."
    pct_exec "$CTID" rm -rf /root/.cache/pip

    # Clone vLLM Repository
    log_info "Cloning vLLM repository..."
    if pct_exec "$CTID" [ -d "${vllm_repo_dir}" ]; then
        log_info "vLLM repository already exists. Pulling latest changes."
        pct_exec "$CTID" git -C "${vllm_repo_dir}" pull
    else
        pct_exec "$CTID" git clone https://github.com/vllm-project/vllm.git "${vllm_repo_dir}"
    fi

    # Build and Install vLLM from Source
    log_info "Building and installing vLLM from source (includes flash-attn)..."
    pct_exec "$CTID" "${vllm_dir}/bin/pip" install -e "${vllm_repo_dir}"
    log_info "Cleaning pip cache after vLLM installation..."
    pct_exec "$CTID" rm -rf /root/.cache/pip

    # Verification
    log_info "Verifying vLLM source installation..."
    if ! pct_exec "$CTID" "${vllm_dir}/bin/python" -c "import vllm; print(vllm.__version__)"; then
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