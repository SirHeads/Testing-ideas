#!/bin/bash
#
# File: phoenix_hypervisor_initial_setup.sh
# Description: Prepares the Proxmox host environment for the Phoenix Hypervisor system.
#              This script performs essential setup tasks, including checking for and
#              installing required tools (jq, curl, ajv-cli), verifying core configuration
#              files and directories, and managing a completion marker file. Comments are
#              optimized for Retrieval Augmented Generation (RAG), facilitating effective
#              chunking and vector database indexing.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script is designed to be idempotent, ensuring that repeated executions do not
# cause issues and only perform necessary actions. It establishes the foundational
# environment required for LXC container orchestration.
#
# Usage:
#   ./phoenix_hypervisor_initial_setup.sh
#
# Requirements:
#   - Root or `sudo` privileges on the Proxmox host.
#   - Internet access for package installations.
#   - Core configuration files present in `/usr/local/phoenix_hypervisor/etc/`.
#
# Exit Codes:
#   0: Success
#   1: General error
#   2: Configuration file missing
#   3: Tool installation failed
#   4: Tool verification failed

# --- Global Variables and Constants ---
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"
HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"
LOG_FILE="/var/log/phoenix_hypervisor_initial_setup.log"
MARKER_FILE="/usr/local/phoenix_hypervisor/lib/.phoenix_hypervisor_initialized"

# --- Logging Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*" | tee -a "$LOG_FILE" | tee -a "$MAIN_LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" | tee -a "$LOG_FILE" | tee -a "$MAIN_LOG_FILE" >&2
}

# --- Exit Function ---
exit_script() {
    local exit_code=$1
    if [ "$exit_code" -eq 0 ]; then
        log_info "Initial setup completed successfully."
    else
        log_error "Initial setup failed with exit code $exit_code."
    fi
    exit "$exit_code"
}

# =====================================================================================
# Function: initialize_environment
# Description: Initializes the script's runtime environment. This involves setting up
#              the dedicated log file for this script, logging the script's start,
#              and verifying the existence of the main hypervisor configuration file.
#
# Parameters: None
#
# Global Variables Accessed:
#   - `HYPERVISOR_CONFIG_FILE`: Path to the main hypervisor configuration.
#   - `LOG_FILE`: Path to this script's specific log file.
#
# Exit Conditions:
#   - Exits with code 2 if `HYPERVISOR_CONFIG_FILE` is not found.
#
# RAG Keywords: environment setup, logging initialization, configuration file verification.
# =====================================================================================
# =====================================================================================
initialize_environment() {
    # Initialize/Clear the log file
    > "$LOG_FILE"
    log_info "Script started: phoenix_hypervisor_initial_setup.sh"

    log_info "Verifying existence of HYPERVISOR_CONFIG_FILE: $HYPERVISOR_CONFIG_FILE"
    if [ ! -f "$HYPERVISOR_CONFIG_FILE" ]; then
        log_error "FATAL: Hypervisor configuration file not found at $HYPERVISOR_CONFIG_FILE."
        exit_script 2
    fi
    log_info "HYPERVISOR_CONFIG_FILE found."
}

# =====================================================================================
# Function: check_and_create_marker
# Description: Checks for the existence of a marker file (`.phoenix_hypervisor_initialized`)
#              to determine if the initial setup has been previously completed. This
#              mechanism ensures idempotency and prevents redundant setup operations.
#
# Parameters: None
#
# Global Variables Modified:
#   - `SETUP_NEEDED`: A boolean flag indicating whether setup steps need to be performed.
#
# Global Variables Accessed:
#   - `MARKER_FILE`: Path to the marker file.
#
# RAG Keywords: idempotency, setup marker, initial setup status, script control flow.
# =====================================================================================
# =====================================================================================
SETUP_NEEDED=true # Global flag to indicate if setup steps need to be performed

check_and_create_marker() {
    log_info "Checking for marker file: $MARKER_FILE"
    if [ -f "$MARKER_FILE" ]; then
        log_info "Marker file found. Initial setup appears to have been completed previously."
        SETUP_NEEDED=false
    else
        log_info "Marker file not found. Initial setup will proceed."
        SETUP_NEEDED=true
    fi
}

# =====================================================================================
# Function: verify_core_config_files
# Description: Verifies the presence and readability of essential configuration files
#              required for the Phoenix Hypervisor system. This includes the main
#              hypervisor config, LXC configs, and their schema definitions.
#
# Parameters: None
#
# Global Variables Accessed:
#   - `HYPERVISOR_CONFIG_FILE`: Path to the main hypervisor configuration.
#
# Dependencies:
#   - `jq`: Used for basic JSON readability checks.
#
# Exit Conditions:
#   - Exits with code 2 if any core configuration file is missing, or is not a valid/readable JSON.
#
# RAG Keywords: configuration file verification, system integrity, JSON schema,
#               LXC configuration, error handling.
# =====================================================================================
# =====================================================================================

verify_core_config_files() {
    local config_files=(
        "$HYPERVISOR_CONFIG_FILE"
        "/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
        "/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json"
    )

    log_info "Verifying core configuration files..."
    for file in "${config_files[@]}"; do
        log_info "Checking file: $file"
        if [ ! -f "$file" ]; then
            log_error "FATAL: Core configuration file not found: $file."
            exit_script 2
        fi
        
        # Optional: Perform a basic readability check using jq
        if ! jq empty < "$file" > /dev/null 2>&1; then
            log_error "ERROR: Core configuration file $file is not a valid JSON file or is unreadable."
            exit_script 2
        fi
        log_info "File $file is present and readable."
    done
    log_info "All core configuration files verified."
}

# =====================================================================================
# Function: install_required_packages
# Description: Installs or verifies the installation of essential system packages
#              and Node.js global modules required by the Phoenix Hypervisor.
#              This includes `jq`, `curl`, `nodejs`, `npm`, and `ajv-cli`.
#              It ensures the host has the necessary command-line tools for script execution.
#
# Parameters: None
#
# Dependencies:
#   - `apt-get`: For Debian/Ubuntu package management.
#   - `npm`: For Node.js package management.
#   - `sudo`: Required for package installations.
#
# Exit Conditions:
#   - Exits with code 3 if `apt-get update` or any package/tool installation fails.
#
# RAG Keywords: package installation, tool dependencies, apt-get, npm, jq, curl,
#               nodejs, ajv-cli, host preparation, error handling.
# =====================================================================================
# =====================================================================================

install_required_packages() {
    local packages=("jq" "curl" "nodejs" "npm")

    log_info "Starting package installation check..."

    log_info "Updating apt package list..."
    if ! sudo apt-get update; then
        log_error "FATAL: Failed to update apt package list."
        exit_script 3
    fi
    log_info "Apt package list updated."

    for package in "${packages[@]}"; do
        log_info "Checking for package: $package"
        if ! dpkg -l "$package" > /dev/null 2>&1; then
            log_info "Package $package not found. Installing..."
            if ! sudo apt-get install -y "$package"; then
                log_error "FATAL: Failed to install package: $package."
                exit_script 3
            fi
            log_info "Package $package installed successfully."
        else
            log_info "Package $package already present."
        fi
    done

    log_info "Checking for ajv-cli..."
    if ! command -v ajv > /dev/null 2>&1; then
        log_info "ajv-cli not found. Installing via npm..."
        if ! sudo npm install -g ajv-cli; then
            log_error "FATAL: Failed to install ajv-cli via npm."
            exit_script 3
        fi
        log_info "ajv-cli installed successfully."
    else
        log_info "ajv-cli already present."
    fi
    log_info "All required packages and tools installed/verified."
}

# =====================================================================================
# Function: verify_required_tools
# Description: Verifies that all critical command-line tools (`jq`, `curl`, `pct`, `ajv`)
#              are installed and accessible in the system's PATH. This is a final check
#              to ensure the environment is fully prepared for subsequent operations.
#
# Parameters: None
#
# Exit Conditions:
#   - Exits with code 4 if any critical tool is not found in the PATH.
#
# RAG Keywords: tool verification, system dependencies, command-line tools,
#               PATH environment, error handling.
# =====================================================================================
# =====================================================================================

verify_required_tools() {
    local tools=("jq" "curl" "pct" "ajv")

    log_info "Starting critical tool verification..."
    for tool in "${tools[@]}"; do
        log_info "Verifying tool: $tool"
        if ! command -v "$tool" > /dev/null 2>&1; then
            log_error "FATAL: Critical tool '$tool' not found in PATH. Please ensure it is installed and accessible."
            exit_script 4
        fi
        log_info "Tool '$tool' verified."
    done
    log_info "All critical tools verified."
}

# =====================================================================================
# Function: ensure_core_directories_exist
# Description: Ensures that the standard directory structure required by the Phoenix
#              Hypervisor is present on the host filesystem. This includes creating
#              `/usr/local/phoenix_hypervisor/bin`, `/etc`, and `/lib` if they do not exist.
#
# Parameters: None
#
# Dependencies:
#   - `mkdir -p`: For creating directories recursively.
#   - `sudo`: Required for creating directories in `/usr/local/`.
#
# Exit Conditions:
#   - Exits with code 1 if any required directory fails to be created.
#
# RAG Keywords: directory structure, filesystem management, host preparation,
#               Phoenix Hypervisor, error handling.
# =====================================================================================
# =====================================================================================

ensure_core_directories_exist() {
    local core_directories=(
        "/usr/local/phoenix_hypervisor/bin"
        "/usr/local/phoenix_hypervisor/etc"
        "/usr/local/phoenix_hypervisor/lib"
    )

    log_info "Ensuring core directories exist..."
    for dir in "${core_directories[@]}"; do
        log_info "Checking/creating directory: $dir"
        if [ ! -d "$dir" ]; then
            if ! sudo mkdir -p "$dir"; then
                log_error "FATAL: Failed to create directory: $dir."
                exit_script 1
            fi
            log_info "Directory $dir created."
        else
            log_info "Directory $dir already exists."
        fi
    done
    log_info "All core directories ensured."
}

# =====================================================================================
# Function: finalize_setup
# Description: Performs final actions upon successful completion of the initial setup steps.
#              This primarily involves creating a marker file to indicate that the setup
#              has been completed, preventing redundant executions in the future.
#
# Parameters: None
#
# Global Variables Accessed:
#   - `SETUP_NEEDED`: Flag indicating if setup actions were performed.
#   - `MARKER_FILE`: Path to the marker file.
#
# Dependencies:
#   - `sudo`: May be required to create the marker file.
#
# RAG Keywords: setup finalization, marker file, idempotency, host configuration.
# =====================================================================================
# =====================================================================================

finalize_setup() {
    log_info "Finalizing setup..."
    if $SETUP_NEEDED; then
        log_info "Creating marker file: $MARKER_FILE"
        if ! sudo touch "$MARKER_FILE"; then
            log_error "WARNING: Failed to create marker file at $MARKER_FILE. Setup considered complete, but marker creation failed."
        else
            log_info "Marker file created."
        fi
    else
        log_info "Setup actions were not performed (marker existed), skipping marker file creation."
    fi
    log_info "Initial host setup is complete."
}

# =====================================================================================
# Function: main
# Description: The main entry point for the initial host setup script.
#              It orchestrates the entire setup process by initializing the environment,
#              checking for previous completion via a marker file, and then conditionally
#              executing core setup steps including configuration file verification,
#              package installation, tool verification, and directory creation.
#
# Parameters: None
#
# Dependencies:
#   - `initialize_environment()`
#   - `check_and_create_marker()`
#   - `verify_core_config_files()`
#   - `install_required_packages()`
#   - `verify_required_tools()`
#   - `ensure_core_directories_exist()`
#   - `finalize_setup()`
#   - `exit_script()`
#
# RAG Keywords: main function, script entry point, host setup flow, idempotency,
#               environment preparation.
# =====================================================================================
# =====================================================================================
main() {
    initialize_environment
    check_and_create_marker

    if $SETUP_NEEDED; then
        log_info "Proceeding with initial setup steps..."
        verify_core_config_files
        install_required_packages
        verify_required_tools
        ensure_core_directories_exist
        finalize_setup
    else
        log_info "Initial setup steps skipped as marker file was found."
    fi

    exit_script 0
}

# Call the main function
main
