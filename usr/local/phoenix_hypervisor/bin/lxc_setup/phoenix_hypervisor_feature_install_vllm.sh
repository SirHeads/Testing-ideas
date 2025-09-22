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
# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "$(dirname "$0")/../phoenix_hypervisor_common_utils.sh"

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
# Function: install_proxy_ca_certificate
# Description: Installs the proxy's root CA certificate into the container's trust store.
#              The certificate is expected to be located at /usr/local/phoenix_hypervisor/etc/certs/proxy_ca.crt
#              on the hypervisor. This function is idempotent.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None.
# =====================================================================================
install_proxy_ca_certificate() {
    log_info "Checking for proxy CA certificate..."
    local hypervisor_cert_path="/usr/local/phoenix_hypervisor/etc/certs/proxy_ca.crt"
    local container_cert_path="/usr/local/share/ca-certificates/proxy_ca.crt"
    local container_cert_dir="/usr/local/share/ca-certificates/"

    # Check if the certificate file exists on the hypervisor
    if [ -f "$hypervisor_cert_path" ]; then
        log_info "Proxy CA certificate found on the hypervisor. Proceeding with installation."

        # Ensure the target directory exists in the container
        pct_exec "$CTID" mkdir -p "$container_cert_dir"

        # Push the certificate to the container
        pct push "$CTID" "$hypervisor_cert_path" "$container_cert_path"

        # Check if the certificate was successfully copied
        if pct_exec "$CTID" test -f "$container_cert_path"; then
            log_info "Successfully copied proxy CA certificate to CTID $CTID."
            # Update the certificate store in the container
            log_info "Updating CA certificates in CTID $CTID..."
            pct_exec "$CTID" update-ca-certificates
            log_info "CA certificates updated successfully."
        else
            log_error "Failed to copy proxy CA certificate to CTID $CTID."
        fi
    else
        log_info "Proxy CA certificate not found at $hypervisor_cert_path. Skipping installation."
    fi
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
    install_proxy_ca_certificate
    log_info "Starting vLLM source installation and verification in CTID: $CTID"

    log_info "Verifying NVIDIA GPU access in CTID $CTID..."
    # Check for NVIDIA GPU access using `nvidia-smi`
    if ! pct_exec "$CTID" nvidia-smi; then
        log_fatal "NVIDIA GPU not accessible in CTID $CTID. Aborting vLLM installation."
    fi
    log_info "NVIDIA GPU access verified."
    local vllm_dir="/opt/vllm" # Directory for vLLM virtual environment
    local vllm_repo_dir="/opt/vllm_repo" # Directory for vLLM source repository

    # Idempotency Check for Template-Based Deployments
    log_info "Checking for existing vLLM installation..."
    if pct_exec "$CTID" test -f "${vllm_dir}/bin/vllm"; then
        log_info "Existing vLLM installation found (vllm executable exists). Skipping feature installation."
        log_info "This is expected when deploying from a pre-built template."
        return 0
    fi
    log_info "No existing vLLM installation found. Proceeding with full installation."

    # Install Python, build tools, and git
    # Install Python 3.11, build tools, and git
    log_info "Installing Python 3.11, build tools, and git in CTID $CTID..."
    pct_exec "$CTID" apt-get update
    pct_exec "$CTID" apt-get install -y software-properties-common
    pct_exec "$CTID" add-apt-repository -y ppa:deadsnakes/ppa
    pct_exec "$CTID" apt-get update
    pct_exec "$CTID" apt-get install -y python3.11-full python3.11-dev python3.11-venv python3-pip build-essential cmake git ninja-build

    # Create vLLM virtual environment
    # Create vLLM Python virtual environment
    log_info "Creating vLLM virtual environment in ${vllm_dir} for CTID $CTID..."
    pct_exec "$CTID" mkdir -p "$vllm_dir"
    pct_exec "$CTID" python3.11 -m venv "$vllm_dir"

    # Upgrade pip
    # Upgrade pip within the new virtual environment
    log_info "Upgrading pip in the new virtual environment..."
    pct_exec "$CTID" "${vllm_dir}/bin/pip" install --upgrade pip

    # Install PyTorch Nightly
    # Install PyTorch Nightly for CUDA 12.8+ compatibility
    log_info "Installing PyTorch nightly for CUDA 12.1+..."
    pct_exec "$CTID" "${vllm_dir}/bin/pip" install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu121
    log_info "Cleaning pip cache after PyTorch installation..."
    pct_exec "$CTID" rm -rf /root/.cache/pip

    # Clone vLLM Repository
    # Clone vLLM Repository or pull latest changes if it exists
    log_info "Cloning vLLM repository..."
    if pct_exec "$CTID" test -d "${vllm_repo_dir}"; then
        log_info "vLLM repository already exists. Fetching latest changes and checking out known-good commit."
        pct_exec "$CTID" git -C "${vllm_repo_dir}" fetch --all
        pct_exec "$CTID" git -C "${vllm_repo_dir}" checkout 5bcc153d7bf69ef34bc5788a33f60f1792cf2861
    else
        pct_exec "$CTID" git clone https://github.com/vllm-project/vllm.git "${vllm_repo_dir}"
        log_info "Checking out known-good vLLM commit..."
        pct_exec "$CTID" git -C "${vllm_repo_dir}" checkout 5bcc153d7bf69ef34bc5788a33f60f1792cf2861
    fi

    # Build and Install vLLM from Source
    # Build and Install vLLM from Source in editable mode (includes flash-attn)
    log_info "Building and installing vLLM from source (includes flash-attn)..."
    pct_exec "$CTID" "${vllm_dir}/bin/pip" install -e "${vllm_repo_dir}"
    log_info "Installing FlashInfer from source..."
    pct_exec "$CTID" rm -rf /opt/flashinfer
    pct_exec "$CTID" git clone https://github.com/flashinfer-ai/flashinfer.git /opt/flashinfer
    pct_exec "$CTID" "${vllm_dir}/bin/pip" install -e /opt/flashinfer
    log_info "Cleaning pip cache after vLLM installation..."
    pct_exec "$CTID" rm -rf /root/.cache/pip

    # Verification
    # Verification: Check vLLM installation by importing and printing its version
    log_info "Verifying vLLM source installation..."
    if ! pct_exec "$CTID" "${vllm_dir}/bin/python" -c "import vllm; print(vllm.__version__)"; then
        log_fatal "vLLM installation verification failed in CTID $CTID."
    fi
    
    log_info "vLLM installation and verification complete for CTID $CTID."
}

# =====================================================================================
# Function: create_vllm_systemd_service
# Description: Creates a generic systemd service file for the vLLM model server.
#              This service file is a template with placeholders that will be
#              dynamically replaced by the container-specific application script.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if the service file cannot be created.
# =====================================================================================
create_vllm_systemd_service() {
    log_info "Creating generic systemd service file for vLLM in CTID: $CTID..."
    local service_file_path="/etc/systemd/system/vllm_model_server.service"
    local temp_service_file
    temp_service_file=$(mktemp) # Create a temporary file on the hypervisor

    # Write the systemd service file content to the temporary file
    cat > "$temp_service_file" <<'EOF'
[Unit]
Description=vLLM Model Server
After=network.target

[Service]
User=root
WorkingDirectory=/opt/vllm
ExecStart=/opt/vllm/bin/python -m vllm.entrypoints.openai.api_server --model "VLLM_MODEL_PLACEHOLDER" --served-model-name "VLLM_SERVED_MODEL_NAME_PLACEHOLDER" --host 0.0.0.0 --port VLLM_PORT_PLACEHOLDER VLLM_ARGS_PLACEHOLDER
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Push the temporary file to the container
    pct push "$CTID" "$temp_service_file" "$service_file_path"

    # Clean up the temporary file
    rm "$temp_service_file"

    # Verify that the file was created
    if ! pct_exec "$CTID" test -f "$service_file_path"; then
        log_fatal "Failed to create systemd service file in CTID $CTID."
    fi

    log_info "Successfully created vLLM systemd service file in CTID $CTID."
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
    create_vllm_systemd_service # Create the systemd service file
    
    exit_script 0 # Exit successfully
}

main "$@"