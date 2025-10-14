#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_base_setup.sh
# Description: This script serves as the foundational modular feature installer for all new LXC containers
#              within the Phoenix Hypervisor ecosystem. Its primary role, as defined in the `features` array
#              of `phoenix_lxc_configs.json`, is to establish a consistent and standardized baseline
#              operating system environment. It automates the installation of essential packages
#              (e.g., curl, wget, vim, htop, jq, git) and configures the system locale to en_US.UTF-8.
#              This ensures that any container, regardless of its final application, starts from a known,
#              stable, and correctly configured state. The script is designed to be idempotent, meaning
#              it can be run multiple times without causing adverse effects, making it a reliable component
#              of the main phoenix_orchestrator.sh workflow.
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: Provides shared functions for logging, command execution, and error handling.
#   - Core system binaries: dpkg, apt-get, grep, bash, locale-gen, update-locale.
#
# Inputs:
#   - $1 (CTID): The unique Container ID for the target LXC container that requires the base setup.
#
# Outputs:
#   - Logs package installation and locale configuration details to stdout and the main log file.
#   - Modifies the container's filesystem by installing packages and setting the locale.
#   - Returns exit code 0 on success, non-zero on failure.
#
# Version: 1.1.0
# Author: Phoenix Hypervisor Team

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Source common utilities ---
# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""

# =====================================================================================
# Function: parse_arguments
# Description: Validates and parses the command-line arguments provided to the script.
#              It expects exactly one argument: the CTID of the target LXC container.
#              This function is critical for ensuring the script targets the correct container
#              for the base OS setup.
# Arguments:
#   $1 - The Container ID (CTID) for the LXC container.
# Globals:
#   - CTID: This global variable is set with the value of $1.
# Returns:
#   - None. The script will exit with status 2 if the required argument is missing.
# =====================================================================================
parse_arguments() {
    # Ensure that the script is called with the Container ID (CTID) as the first argument.
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        log_error "This script requires the LXC Container ID as an argument to perform the base OS setup."
        exit_script 2
    fi
    # Assign the provided argument to the global CTID variable for use throughout the script.
    CTID="$1"
    log_info "Executing Base Setup modular feature for CTID: $CTID"
}

# =====================================================================================
# Function: perform_base_os_setup
# Description: Orchestrates the core logic for the base OS setup within the target LXC container.
#              This function handles two main responsibilities:
#              1. Package Management: It checks for a list of essential packages and installs any that are missing.
#                 This uses an idempotency check to avoid reinstalling packages, making the process efficient.
#              2. Locale Configuration: It sets the system-wide locale to en_US.UTF-8, which is a standard
#                 prerequisite for many applications to function correctly.
# Arguments:
#   None. It relies on the global CTID variable set by `parse_arguments`.
# Returns:
#   - None. The script will exit via `exit_script` if a critical command fails,
#     thanks to `set -e` and the error handling in `pct_exec`.
# =====================================================================================
perform_base_os_setup() {
    log_info "Performing base OS setup in CTID: $CTID"

    # --- Idempotency Check & Package Installation ---
    log_info "Verifying essential packages in CTID $CTID..."
    local essential_packages=("curl" "wget" "vim" "htop" "jq" "git" "rsync" "s-tui" "gnupg" "locales")
    local packages_to_install=()
    local packages_found=()

    for pkg in "${essential_packages[@]}"; do
        if is_command_available "$CTID" "$pkg"; then
            packages_found+=("$pkg")
        else
            packages_to_install+=("$pkg")
        fi
    done

    if [ ${#packages_found[@]} -gt 0 ]; then
        log_info "Found packages: ${packages_found[*]}"
    fi

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_info "Missing packages: ${packages_to_install[*]}. Installing..."
        # Force set DNS before running apt-get update
        local fallback_dns="8.8.8.8"
        log_info "Forcing DNS to fallback DNS: $fallback_dns"
        pct_exec "$CTID" -- bash -c "echo 'nameserver $fallback_dns' > /etc/resolv.conf" || log_fatal "Failed to force DNS update in container."
        
        pct_exec "$CTID" apt-get update
        pct_exec "$CTID" apt-get install -y "${packages_to_install[@]}"
    else
        log_info "All essential packages are already installed."
    fi

    # --- Locale Configuration ---
    log_info "Configuring locale to en_US.UTF-8..."
    pct_exec "$CTID" sed -i 's/^# *\\(en_US.UTF-8\\)/\\1/' /etc/locale.gen
    pct_exec "$CTID" locale-gen en_US.UTF-8
    pct_exec "$CTID" update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
    log_info "Locale configuration complete."

    log_info "Base OS setup complete for CTID $CTID."
}

# =====================================================================================
# Function: main
# Description: The main entry point for the script execution. It orchestrates the
#              workflow by calling the necessary functions in the correct order:
#              1. Parse command-line arguments to get the CTID.
#              2. Perform the base OS setup, including package installation and locale configuration.
#              3. Exit with a success status.
# Arguments:
#   $@ - All command-line arguments passed to the script, which are then forwarded
#        to the `parse_arguments` function.
# Returns:
#   - Exits with status 0 on successful completion of all tasks.
# =====================================================================================
main() {
    # The first step is to parse and validate the command-line arguments.
    parse_arguments "$@"

    # Note: The original idempotency check `_check_base_setup_installed` was removed
    # because the checks within `perform_base_os_setup` (package and locale checks)
    # provide a more granular and reliable form of idempotency.

    # Execute the core logic of the script.
    perform_base_os_setup

    # Conclude the script with a success message and exit code.
    log_info "Successfully completed base setup feature for CTID $CTID."
    exit_script 0
}

# This final line executes the main function, passing all command-line arguments to it.
# This is the standard way to start the execution of a bash script.
main "$@"