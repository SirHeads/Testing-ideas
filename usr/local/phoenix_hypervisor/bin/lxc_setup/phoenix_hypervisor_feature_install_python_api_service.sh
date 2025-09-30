#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_python_api_service.sh
# Description: This script serves as a foundational feature installer for enabling Python-based
#              applications and services within an LXC container. Its primary purpose is to install
#              the core components of a modern Python development environment, including Python 3,
#              the pip package installer, and the `venv` module for creating isolated virtual
#              environments. This modular feature is a prerequisite for other features like `vllm`
#              that depend on a Python runtime. It ensures a consistent and reliable Python
#              environment is established before application-specific dependencies are installed.
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - `apt-get`: For package installation.
#
# Inputs:
#   - $1 (CTID): The unique Container ID for the target LXC container.
#
# Outputs:
#   - Installs python3, python3-pip, and python3-venv packages inside the container.
#   - Logs the installation process to stdout and the main log file.
#   - Returns exit code 0 on success, non-zero on failure.
#
# Version: 1.1.0
# Author: Phoenix Hypervisor Team

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""

# =====================================================================================
# Function: parse_arguments
# Description: Validates and parses the command-line arguments to get the CTID.
# Arguments:
#   $1 - The Container ID (CTID).
# Globals:
#   - CTID: Sets the global CTID variable.
# Returns:
#   - None. Exits with status 2 if the CTID is not provided.
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        log_error "This script requires the LXC Container ID to set up the Python environment."
        exit_script 2
    fi
    CTID="$1"
    log_info "Executing Python API Service Environment setup feature for CTID: $CTID"
}

# =====================================================================================
# Function: setup_python_environment
# Description: Installs the core Python packages required for API services.
# Arguments:
#   None. Relies on the global CTID.
# Returns:
#   - None. Exits on failure.
# =====================================================================================
setup_python_environment() {
    # Idempotency Check: Verify if python3 is already installed.
    if is_command_available "$CTID" "python3"; then
        log_info "Python 3 is already installed. Ensuring pip and venv are also present."
    else
        log_info "Python 3 not found. Proceeding with installation."
    fi

    log_info "Updating package lists in CTID $CTID..."
    pct_exec "$CTID" -- apt-get update

    log_info "Installing Python 3, pip, and venv packages in CTID $CTID..."
    # This command ensures that the complete toolchain for a virtual environment-based
    # Python workflow is available in the container.
    if ! pct_exec "$CTID" -- apt-get install -y python3 python3-pip python3-venv python3.10-venv; then
        log_fatal "Failed to install Python packages in CTID $CTID."
    fi

    log_success "Python environment packages installed successfully."
}

# =====================================================================================
# Function: verify_installation
# Description: Verifies that the Python components were installed correctly.
# Arguments:
#   None. Relies on the global CTID.
# Returns:
#   - None. Exits with a fatal error if verification fails.
# =====================================================================================
verify_installation() {
    log_info "Verifying Python installation in CTID: $CTID"
    if ! is_command_available "$CTID" "python3"; then
        log_fatal "Verification failed: 'python3' command not found."
    fi
    if ! is_command_available "$CTID" "pip3"; then
        log_fatal "Verification failed: 'pip3' command not found."
    fi
    log_success "Python installation verified successfully."
}

# =====================================================================================
# Function: main
# Description: Main entry point for the Python API service environment setup script.
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   - Exits with status 0 on successful completion.
# =====================================================================================
main() {
    parse_arguments "$@"
    setup_python_environment
    verify_installation
    log_info "Successfully completed Python API Service environment setup for CTID $CTID."
    exit_script 0
}

# Execute the main function
main "$@"