#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_vllm.sh
# File: phoenix_hypervisor_feature_install_vllm.sh
# Description: Automates the installation and verification of the vLLM inference server
#              from source within a Proxmox LXC container. This script ensures NVIDIA
#              GPU access, installs Python and build tools, sets up a Python virtual
#              environment, installs PyTorch nightly, clones the vLLM repository,
#              builds and installs vLLM from source, and verifies the installation.
#              It is designed to be idempotent and is typically called by the main orchestrator.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), pct, nvidia-smi,
#               apt-get, software-properties-common, add-apt-repository, python3.11-full,
#               python3.11-dev, python3.11-venv, python3-pip, build-essential, cmake,
#               git, mkdir, python3.11, pip, rm, grep.
# Inputs:
#   $1 (CTID) - The container ID for the LXC container.
# Outputs:
#   Package installation logs, virtual environment creation, PyTorch and vLLM
#   installation logs, vLLM version output for verification, log messages to stdout
#   and MAIN_LOG_FILE, exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Source common utilities ---
source "$(dirname "$0")/phoenix_hypervisor_common_utils.sh" # Source common utilities for logging and error handling

# --- Script Variables ---
CTID=""

# =====================================================================================
# Function: parse_arguments
# Description: Parses the CTID from command-line arguments.
# =====================================================================================
# =====================================================================================
# Function: parse_arguments
# Description: Parses command-line arguments to extract the Container ID (CTID).
# Arguments:
#   $1 - The Container ID (CTID) for the LXC container.
# Returns:
#   Exits with status 2 if no CTID is provided.
# =====================================================================================
parse_arguments() {
    # Check if exactly one argument (CTID) is provided
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1" # Assign the first argument to CTID
    log_info "Executing vLLM feature for CTID: $CTID"
}

# =====================================================================================
# Function: install_and_test_vllm
# Description: Orchestrates the installation of vLLM from source and verifies its
#              functionality.
# =====================================================================================
# =====================================================================================
# Function: install_and_test_vllm
# Description: Orchestrates the complete installation of the vLLM inference server
#              from source and verifies its functionality within the LXC container.
#              This includes GPU access verification, Python environment setup,
#              PyTorch installation, vLLM repository cloning, and source installation.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if GPU access fails or any installation/verification step fails.
# =====================================================================================
install_and_test_vllm() {
    log_info "Starting vLLM source installation and verification in CTID: $CTID"

    log_info "Verifying NVIDIA GPU access in CTID $CTID..."
    # Check for NVIDIA GPU access using `nvidia-smi`
    if ! pct_exec "$CTID" nvidia-smi; then
        log_fatal "NVIDIA GPU not accessible in CTID $CTID. Aborting vLLM installation."
    fi
    log_info "NVIDIA GPU access verified."
    local vllm_dir="/opt/vllm" # Directory for vLLM virtual environment
    local vllm_repo_dir="/opt/vllm_repo" # Directory for vLLM source repository

    # Idempotency Check: Check if vLLM is installed in editable mode.
    # Idempotency Check: Check if vLLM is already installed from source in editable mode
    if pct_exec "$CTID" "${vllm_dir}/bin/pip" list | grep -q "vllm.*${vllm_repo_dir}"; then
        log_info "vLLM appears to be installed from source in CTID $CTID. Skipping installation."
        return 0
    fi

    # Install Python, build tools, and git
    # Install Python 3.11, build tools, and git
    log_info "Installing Python 3.11, build tools, and git in CTID $CTID..."
    pct_exec "$CTID" apt-get update # Update package lists
    pct_exec "$CTID" apt-get install -y software-properties-common # Install software-properties-common
    pct_exec "$CTID" add-apt-repository -y ppa:deadsnakes/ppa # Add deadsnakes PPA for Python 3.11
    pct_exec "$CTID" apt-get update # Update package lists again
    pct_exec "$CTID" apt-get install -y python3.11-full python3.11-dev python3.11-venv python3-pip build-essential cmake git # Install Python 3.11 and development tools

    # Create vLLM virtual environment
    # Create vLLM Python virtual environment
    log_info "Creating vLLM virtual environment in ${vllm_dir} for CTID $CTID..."
    pct_exec "$CTID" mkdir -p "$vllm_dir" # Create virtual environment directory
    pct_exec "$CTID" python3.11 -m venv "$vllm_dir" # Create virtual environment

    # Upgrade pip
    # Upgrade pip within the new virtual environment
    log_info "Upgrading pip in the new virtual environment..."
    pct_exec "$CTID" "${vllm_dir}/bin/pip" install --upgrade pip # Upgrade pip

    # Install PyTorch Nightly
    # Install PyTorch Nightly for CUDA 12.8+ compatibility
    log_info "Installing PyTorch nightly for CUDA 12.8+..."
    pct_exec "$CTID" "${vllm_dir}/bin/pip" install --pre torch --index-url https://download.pytorch.org/whl/nightly/cu128 # Install PyTorch
    log_info "Cleaning pip cache after PyTorch installation..."
    pct_exec "$CTID" rm -rf /root/.cache/pip # Clean pip cache

    # Clone vLLM Repository
    # Clone vLLM Repository or pull latest changes if it exists
    log_info "Cloning vLLM repository..."
    if pct_exec "$CTID" [ -d "${vllm_repo_dir}" ]; then # Check if repository already exists
        log_info "vLLM repository already exists. Pulling latest changes."
        pct_exec "$CTID" git -C "${vllm_repo_dir}" pull # Pull latest changes
    else
        pct_exec "$CTID" git clone https://github.com/vllm-project/vllm.git "${vllm_repo_dir}" # Clone repository
    fi

    # Build and Install vLLM from Source
    # Build and Install vLLM from Source in editable mode (includes flash-attn)
    log_info "Building and installing vLLM from source (includes flash-attn)..."
    pct_exec "$CTID" "${vllm_dir}/bin/pip" install -e "${vllm_repo_dir}" # Install vLLM from source
    log_info "Cleaning pip cache after vLLM installation..."
    pct_exec "$CTID" rm -rf /root/.cache/pip # Clean pip cache

    # Verification
    # Verification: Check vLLM installation by importing and printing its version
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
# =====================================================================================
# Function: main
# Description: Main entry point for the vLLM feature script.
#              It parses arguments, installs and tests vLLM, and exits.
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   Exits with status 0 on successful completion.
# =====================================================================================
main() {
    parse_arguments "$@" # Parse command-line arguments
    install_and_test_vllm # Install and test vLLM
    exit_script 0 # Exit successfully
}

main "$@"