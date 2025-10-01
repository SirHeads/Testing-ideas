#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_vllm.sh
# File: phoenix_hypervisor_feature_install_vllm.sh
# Description: This modular feature script automates the complete setup of the vLLM (vLLM)
#              inference engine from source within an LXC container. It prepares the container
#              to serve high-throughput large language models by performing a series of critical
#              steps: verifying GPU access, installing a specific Python version and build tools,
#              creating an isolated Python virtual environment, installing a compatible nightly
#              build of PyTorch, and finally, building and installing vLLM from a pinned commit
#              in its source repository. It also creates a generic systemd service file that acts
#              as a template for the final application runner script.
#
# Dependencies:
#   - The 'nvidia' and 'python_api_service' features must be installed first.
#   - phoenix_hypervisor_common_utils.sh: For shared functions.
#   - Internet access for downloading packages and cloning the git repository.
#
# Inputs:
#   - $1 (CTID): The unique Container ID for the target LXC container.
#
# Outputs:
#   - A complete vLLM installation within a Python virtual environment at /opt/vllm.
#   - A generic systemd service template at /etc/systemd/system/vllm_model_server.service.
#   - Logs the entire build and installation process.
#   - Returns exit code 0 on success, non-zero on failure.
#
# Version: 1.1.0
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
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        log_error "This script requires the LXC Container ID to install the vLLM feature."
        exit_script 2
    fi
    CTID="$1"
    log_info "Executing vLLM modular feature for CTID: $CTID"
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
        run_pct_push "$CTID" "$hypervisor_cert_path" "$container_cert_path"

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

    # --- Dependency Check ---
    # vLLM requires NVIDIA drivers to function.
    log_info "Verifying 'nvidia' feature dependency..."
    if ! is_feature_present_on_container "$CTID" "nvidia"; then
        log_fatal "The 'vllm' feature requires the 'nvidia' feature, which was not found."
    fi
    if ! is_command_available "$CTID" "nvidia-smi"; then
        log_fatal "NVIDIA driver command 'nvidia-smi' not found. The 'vllm' feature depends on a functional NVIDIA driver."
    fi

    # This is a critical check to ensure the GPU is properly passed through to the container.
    log_info "Verifying NVIDIA GPU access in CTID $CTID..."
    if ! pct_exec "$CTID" -- nvidia-smi; then
        log_fatal "NVIDIA GPU not accessible in CTID $CTID. 'nvidia-smi' command failed."
    fi
    log_success "NVIDIA GPU access verified."

    local vllm_dir="/opt/vllm"
    local vllm_repo_dir="/opt/vllm_repo"

    # --- Idempotency Check ---
    # This check is crucial for template-based deployments where vLLM is pre-installed.
    log_info "Checking for existing vLLM installation at ${vllm_dir}/bin/python..."
    if pct_exec "$CTID" -- test -f "${vllm_dir}/bin/python"; then
        log_info "Existing vLLM installation found. Skipping feature installation."
        return 0
    fi
    log_info "No existing vLLM installation found. Proceeding with full source installation."

    # --- Environment Setup ---
    # Using a specific Python version (3.11) ensures a consistent and reproducible build environment.
    log_info "Installing Python 3.11, build tools, and git..."
    pct_exec "$CTID" -- apt-get update
    pct_exec "$CTID" -- apt-get install -y software-properties-common
    pct_exec "$CTID" -- add-apt-repository -y ppa:deadsnakes/ppa
    pct_exec "$CTID" -- apt-get update
    pct_exec "$CTID" -- apt-get install -y python3.11-full python3.11-dev python3.11-venv python3-pip build-essential cmake git ninja-build

    # A virtual environment is essential for isolating vLLM's dependencies from system packages.
    log_info "Creating Python virtual environment in ${vllm_dir}..."
    pct_exec "$CTID" -- mkdir -p "$vllm_dir"
    pct_exec "$CTID" -- python3.11 -m venv "$vllm_dir"
    pct_exec "$CTID" -- "${vllm_dir}/bin/pip" install --upgrade pip

    # --- Core Library Installation ---
    # vLLM often requires the latest features from PyTorch, necessitating a nightly build.
    log_info "Installing PyTorch nightly for CUDA 12.1+..."
    pct_exec "$CTID" -- "${vllm_dir}/bin/pip" install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu121

    # --- vLLM Source Installation ---
    # We clone the repository and check out a specific, known-good commit to ensure stability and prevent
    # breaking changes from the main branch affecting our deployments.
    log_info "Cloning vLLM repository and checking out a known-good commit..."
    if pct_exec "$CTID" -- test -d "${vllm_repo_dir}"; then
        log_warn "vLLM repository already exists. Fetching latest changes."
        pct_exec "$CTID" -- git -C "${vllm_repo_dir}" fetch --all
    else
        pct_exec "$CTID" -- git clone https://github.com/vllm-project/vllm.git "${vllm_repo_dir}"
    fi
    pct_exec "$CTID" -- git -C "${vllm_repo_dir}" checkout 5bcc153d7bf69ef34bc5788a33f60f1792cf2861

    # Installing in editable mode (-e) is useful for development and debugging.
    log_info "Building and installing vLLM and FlashInfer from source..."
    pct_exec "$CTID" -- "${vllm_dir}/bin/pip" install -e "${vllm_repo_dir}"
    
    # FlashInfer is a dependency for optimized attention kernels.
    if pct_exec "$CTID" -- test -d "/opt/flashinfer"; then
        log_info "FlashInfer directory already exists. Skipping clone and install."
    else
        pct_exec "$CTID" -- git clone https://github.com/flashinfer-ai/flashinfer.git /opt/flashinfer
        pct_exec "$CTID" -- "${vllm_dir}/bin/pip" install -e /opt/flashinfer
    fi

    # --- Verification ---
    # This final check confirms that the vLLM library is correctly installed in the virtual environment.
    log_info "Verifying vLLM installation by checking the version..."
    if ! pct_exec "$CTID" -- "${vllm_dir}/bin/python" -c "import vllm; print(vllm.__version__)"; then
        log_fatal "vLLM installation verification failed."
    fi
    
    log_success "vLLM source installation and verification complete."
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
Environment="PATH=/usr/local/cuda-12.8/bin:/opt/vllm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/opt/vllm/bin/python -m vllm.entrypoints.openai.api_server --model "VLLM_MODEL_PLACEHOLDER" --served-model-name "VLLM_SERVED_MODEL_NAME_PLACEHOLDER" --host 0.0.0.0 --port VLLM_PORT_PLACEHOLDER VLLM_ARGS_PLACEHOLDER
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Push the temporary file to the container
    run_pct_push "$CTID" "$temp_service_file" "$service_file_path"

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
    parse_arguments "$@"
    install_and_test_vllm
    create_vllm_systemd_service
    log_info "Successfully completed vLLM feature for CTID $CTID."
    exit_script 0
}

main "$@"