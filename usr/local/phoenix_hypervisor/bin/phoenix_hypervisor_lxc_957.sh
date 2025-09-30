#!/bin/bash

# File: phoenix_hypervisor_lxc_957.sh
# Description: This script automates the complete setup of the Llama.cpp environment within LXC container 957.
#              It serves as the final application-specific step in the orchestration process for this container.
#              The script handles the installation of all necessary dependencies, clones the official Llama.cpp
#              repository, and compiles the source code with NVIDIA GPU support (cuBLAS) to enable hardware
#              acceleration for large language models. It concludes with health checks to ensure the compilation
#              was successful and the GPU is accessible.
#
# Dependencies: - A Debian-based LXC container environment.
#               - `git`, `build-essential`, `cmake` for compiling.
#               - An NVIDIA GPU passed through to the container.
#               - The NVIDIA CUDA Toolkit (expected to be installed by a preceding feature script).
#
# Inputs: - CTID (Container ID): Implicitly 957.
#
# Outputs: - A compiled set of Llama.cpp binaries located in `/opt/llama.cpp/build/bin/`.
#          - Log files detailing the installation and compilation process at `/var/log/phoenix_hypervisor_lxc_957.log`.

# --- Script Initialization ---
# set -e: Exit immediately if a command exits with a non-zero status.
# set -u: Treat unset variables as an error.
# set -o pipefail: The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -euo pipefail

# --- Configuration Variables ---
LOG_FILE="/var/log/phoenix_hypervisor_lxc_957.log"
LLAMA_CPP_DIR="/opt/llama.cpp"
IP_ADDRESS="10.0.0.157"
PORT="8081" # Default port for the Llama.cpp server binary.

# --- Environment Setup ---
# Ensure the NVIDIA CUDA compiler and tools are accessible from the PATH.
# This is crucial for compiling with GPU support.
export PATH=$PATH:/usr/local/cuda/bin

# =====================================================================================
# Function: log_message
# Description: Logs a message with a timestamp to both standard output and the designated log file.
# Arguments:
#   $1 - The message string to be logged.
# Returns: None.
# =====================================================================================
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# =====================================================================================
# Function: command_exists
# Description: Checks if a command is available in the system's PATH.
# Arguments:
#   $1 - The command name to check.
# Returns: 0 if the command exists, 1 otherwise.
# =====================================================================================
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

log_message "Starting setup for Llama.cpp Base LXC container (ID 957)..."

# =====================================================================================
# Function: install_dependencies
# Description: Updates package lists and installs essential packages required for compiling Llama.cpp.
# Arguments: None.
# Returns: Exits with status 1 if dependency installation fails.
# =====================================================================================
install_dependencies() {
    log_message "Installing required packages: build-essential, cmake, git..."
    apt update -y >> "$LOG_FILE" 2>&1
    if ! apt install -y build-essential cmake git >> "$LOG_FILE" 2>&1; then
        log_message "ERROR: Failed to install dependencies. Check the log at ${LOG_FILE}. Exiting."
        exit 1
    fi
    log_message "Dependencies installed successfully."
}

# =====================================================================================
# Function: clone_or_update_llama_cpp
# Description: Clones the Llama.cpp repository from GitHub. If the repository already
#              exists, it pulls the latest changes to ensure the build is up-to-date.
# Arguments: None (uses global LLAMA_CPP_DIR).
# Returns: Exits with status 1 if cloning or updating fails.
# =====================================================================================
clone_or_update_llama_cpp() {
    log_message "Cloning or updating Llama.cpp repository in $LLAMA_CPP_DIR..."
    if [ -d "$LLAMA_CPP_DIR" ]; then
        log_message "Llama.cpp directory already exists. Pulling latest changes."
        if ! git -C "$LLAMA_CPP_DIR" pull >> "$LOG_FILE" 2>&1; then
            log_message "ERROR: Failed to pull latest changes for Llama.cpp. Exiting."
            exit 1
        fi
    else
        if ! git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_CPP_DIR" >> "$LOG_FILE" 2>&1; then
            log_message "ERROR: Failed to clone Llama.cpp repository. Exiting."
            exit 1
        fi
    fi
    log_message "Llama.cpp repository is up to date."
}

# =====================================================================================
# Function: compile_llama_cpp
# Description: Compiles the Llama.cpp source code. It checks for the NVIDIA CUDA compiler (`nvcc`)
#              to determine if GPU-accelerated (cuBLAS) compilation is possible.
# Arguments: None (uses global LLAMA_CPP_DIR).
# Returns: Exits with status 1 if compilation fails.
# =====================================================================================
compile_llama_cpp() {
    log_message "Compiling Llama.cpp..."
    cd "$LLAMA_CPP_DIR" || { log_message "ERROR: Failed to change directory to $LLAMA_CPP_DIR. Exiting."; exit 1; }

    # Check for `nvcc` to enable GPU support. This is the preferred compilation mode for performance.
    if command_exists nvcc; then
        log_message "NVIDIA CUDA compiler (nvcc) found. Compiling with cuBLAS support for GPU acceleration."
        cmake -B build -DGGML_CUDA=ON -DLLAMA_CURL=OFF
    else
        log_message "WARNING: nvcc not found. Compiling Llama.cpp for CPU only. For GPU support, ensure the 'nvidia' feature is enabled."
        cmake -B build -DLLAMA_CURL=OFF
    fi
    
    log_message "Building the project using $(nproc) cores..."
    if ! cmake --build build --config Release -- -j"$(nproc)" >> "$LOG_FILE" 2>&1; then
        log_message "ERROR: Failed to compile Llama.cpp. Check ${LOG_FILE} for details. Exiting."
        exit 1
    fi
    log_message "Llama.cpp compiled successfully."
}

# =====================================================================================
# Function: perform_health_checks
# Description: Verifies the successful compilation by checking for key binaries (`llama-cli`, `server`).
#              It also checks the NVIDIA GPU status using `nvidia-smi` if available.
# Arguments: None (uses global LLAMA_CPP_DIR).
# Returns: Exits with status 1 if the critical `llama-cli` binary is not found.
# =====================================================================================
perform_health_checks() {
    log_message "Performing health checks..."

    # Verify that the main command-line interface binary was created.
    if [ -f "$LLAMA_CPP_DIR/build/bin/llama-cli" ]; then
        log_message "Health Check PASSED: 'llama-cli' binary found."
    else
        log_message "ERROR: Health Check FAILED: 'llama-cli' binary not found. Compilation failed."
        exit 1
    fi

    # Verify that the server binary was created.
    if [ -f "$LLAMA_CPP_DIR/build/bin/server" ]; then
        log_message "Health Check PASSED: 'server' binary found."
    else
        log_message "WARNING: 'server' binary not found. This may be expected depending on the build configuration."
    fi

    # Check NVIDIA GPU status if `nvidia-smi` is available.
    if command_exists nvidia-smi; then
        log_message "Checking NVIDIA GPU status..."
        nvidia-smi >> "$LOG_FILE" 2>&1 || log_message "WARNING: nvidia-smi command failed. GPU might not be fully functional."
    else
        log_message "WARNING: nvidia-smi not found. Cannot verify GPU status."
    fi
}

# =====================================================================================
# Function: display_info
# Description: Displays a summary of the setup, including the location of the compiled binaries.
# Arguments: None (uses global variables).
# Returns: None.
# =====================================================================================
display_info() {
    log_message "Setup complete for Llama.cpp Base LXC container (ID 957)."
    log_message "Llama.cpp binaries are located in $LLAMA_CPP_DIR/build/bin/."
    log_message "To run the server, use the 'server' binary. It will be accessible at http://$IP_ADDRESS:$PORT by default."
}

# =====================================================================================
# Main execution flow of the script.
# =====================================================================================
main() {
    install_dependencies
    clone_or_update_llama_cpp
    compile_llama_cpp
    perform_health_checks
    display_info
    exit 0
}

# Execute the main function, passing all script arguments to it.
main "$@"