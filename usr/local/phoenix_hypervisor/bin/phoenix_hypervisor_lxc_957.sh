#!/bin/bash

# LXC Container 957: llamacppBase - Setup Script

# This script automates the setup of the llamacppBase LXC container.
# It installs necessary dependencies, clones the llama.cpp repository,
# compiles it with GPU (cuBLAS) support, and performs basic health checks.

set -euo pipefail # Exit immediately if a command exits with a non-zero status, exit on unset variables, exit on pipefail.

LOG_FILE="/var/log/phoenix_hypervisor_lxc_957.log"
LLAMA_CPP_DIR="/opt/llama.cpp"
IP_ADDRESS="10.0.0.157"
PORT="8080" # Default llama.cpp server port

# =====================================================================================
# Function: log_message
# Description: Logs a message to both stdout and a specified log file.
# Arguments:
#   $1 - The message string to be logged.
# Returns:
#   None.
# =====================================================================================
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE" # Prepend timestamp and tee output to stdout and log file
}

# =====================================================================================
# Function: command_exists
# Description: Checks if a given command is available in the system's PATH.
# Arguments:
#   $1 - The command name to check.
# Returns:
#   0 if the command exists, 1 otherwise.
# =====================================================================================
command_exists() {
    command -v "$1" >/dev/null 2>&1 # Check if command exists and suppress output
}

log_message "Starting setup for llamacppBase LXC container (ID 957)..."

# 1. Install Dependencies
log_message "Installing required packages: build-essential, cmake, git..."
apt update -y >> "$LOG_FILE" 2>&1
apt install -y build-essential cmake git >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log_message "Dependencies installed successfully."
else
    log_message "ERROR: Failed to install dependencies. Exiting."
    exit 1
fi

# =====================================================================================
# Function: clone_or_update_llama_cpp
# Description: Clones the llama.cpp repository or pulls the latest changes if it already exists.
# Arguments:
#   None (uses global LLAMA_CPP_DIR).
# Returns:
#   Exits with status 1 if cloning or updating fails.
# =====================================================================================
clone_or_update_llama_cpp() {
    log_message "Cloning llama.cpp repository into $LLAMA_CPP_DIR..."
    # Check if the llama.cpp directory already exists
    if [ -d "$LLAMA_CPP_DIR" ]; then
        log_message "llama.cpp directory already exists. Pulling latest changes."
        git -C "$LLAMA_CPP_DIR" pull >> "$LOG_FILE" 2>&1 # Pull latest changes
    else
        git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_CPP_DIR" >> "$LOG_FILE" 2>&1 # Clone the repository
    fi
    
    if [ $? -eq 0 ]; then
        log_message "llama.cpp repository cloned/updated successfully."
    else
        log_message "ERROR: Failed to clone/update llama.cpp repository. Exiting."
        exit 1
    fi
}

if [ $? -eq 0 ]; then
    log_message "llama.cpp repository cloned/updated successfully."
else
    log_message "ERROR: Failed to clone/update llama.cpp repository. Exiting."
    exit 1
fi

# =====================================================================================
# Function: compile_llama_cpp
# Description: Compiles the llama.cpp project with optional cuBLAS (GPU) support.
#              It checks for the presence of `nvcc` to determine if cuBLAS compilation
#              is possible.
# Arguments:
#   None (uses global LLAMA_CPP_DIR).
# Returns:
#   Exits with status 1 if compilation fails.
# =====================================================================================
compile_llama_cpp() {
    log_message "Compiling llama.cpp with cuBLAS support..."
    cd "$LLAMA_CPP_DIR" || { log_message "ERROR: Failed to change directory to $LLAMA_CPP_DIR. Exiting."; exit 1; } # Change to llama.cpp directory

    # Ensure NVIDIA CUDA is available and configured by the 'nvidia' feature script.
    # The 'nvidia' feature script should have already set up CUDA_PATH and added to PATH.
    if command_exists nvcc; then
        log_message "nvcc found. Proceeding with cuBLAS compilation."
        make clean >> "$LOG_FILE" 2>&1 # Clean previous builds
        LLAMA_CUBLAS=1 make -j$(nproc) >> "$LOG_FILE" 2>&1 # Compile with cuBLAS for GPU acceleration
    else
        log_message "WARNING: nvcc not found. Compiling llama.cpp without cuBLAS support. " \
                    "Ensure the 'nvidia' feature script ran successfully and CUDA is in PATH."
        make clean >> "$LOG_FILE" 2>&1 # Clean previous builds
        make -j$(nproc) >> "$LOG_FILE" 2>&1 # Compile without cuBLAS
    fi
    
    if [ $? -eq 0 ]; then
        log_message "llama.cpp compiled successfully."
    else
        log_message "ERROR: Failed to compile llama.cpp. Check $LOG_FILE for details. Exiting."
        exit 1
    fi
}

if [ $? -eq 0 ]; then
    log_message "llama.cpp compiled successfully."
else
    log_message "ERROR: Failed to compile llama.cpp. Check $LOG_FILE for details. Exiting."
    exit 1
fi

# =====================================================================================
# Function: perform_health_checks
# Description: Performs various health checks to verify the successful compilation
#              of llama.cpp binaries and the status of NVIDIA GPU.
# Arguments:
#   None (uses global LLAMA_CPP_DIR).
# Returns:
#   Exits with status 1 if critical binaries are not found.
# =====================================================================================
perform_health_checks() {
    log_message "Performing health checks..."

    # Check for the presence of the main binary
    if [ -f "$LLAMA_CPP_DIR/main" ]; then
        log_message "llama.cpp 'main' binary found."
    else
        log_message "ERROR: llama.cpp 'main' binary not found. Compilation might have failed."
        exit 1
    fi

    # Check for the presence of the server binary
    if [ -f "$LLAMA_CPP_DIR/server" ]; then
        log_message "llama.cpp 'server' binary found."
    else
        log_message "WARNING: llama.cpp 'server' binary not found. This might be expected if not building the server."
    fi

    # Check NVIDIA GPU status using nvidia-smi if available
    if command_exists nvidia-smi; then
        log_message "NVIDIA GPU status:"
        nvidia-smi >> "$LOG_FILE" 2>&1 || log_message "WARNING: nvidia-smi command failed. GPU might not be fully functional."
    else
        log_message "WARNING: nvidia-smi not found. Cannot verify GPU status."
    fi
}

# =====================================================================================
# Function: display_info
# Description: Displays final information about the llama.cpp setup.
# Arguments:
#   None (uses global LLAMA_CPP_DIR, IP_ADDRESS, PORT).
# Returns:
#   None.
# =====================================================================================
display_info() {
    log_message "Setup complete for llamacppBase LXC container (ID 957)."
    log_message "llama.cpp binaries are located in $LLAMA_CPP_DIR."
    log_message "If running the llama.cpp server, it will typically be accessible at http://$IP_ADDRESS:$PORT (default port)."
}

# Main execution flow
main() {
    log_message "Starting setup for llamacppBase LXC container (ID 957)..."
    install_dependencies
    clone_or_update_llama_cpp
    compile_llama_cpp
    perform_health_checks
    display_info
    exit 0
}

main "$@"