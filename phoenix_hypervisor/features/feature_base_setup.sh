#!/bin/bash
#
# File: feature_base_setup.sh
# Description: This feature script automates the basic OS configuration for a new
#              LXC container. It installs essential packages and sets the system locale.
#              It is designed to be called by the main orchestrator and is fully idempotent.
# Version: 1.0.0
# Author: Roo (AI Engineer)

# --- Source common utilities ---
source "$(dirname "$0")/../bin/phoenix_hypervisor_common_utils.sh"

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
    log_info "Executing Base Setup feature for CTID: $CTID"
}

# =====================================================================================
# Function: perform_base_os_setup
# Description: Installs essential packages and configures the OS.
# =====================================================================================
perform_base_os_setup() {
    log_info "Performing base OS setup in CTID: $CTID"

    # Idempotency Check: Use a marker file to see if this has run before
    local marker_file="/.phoenix_base_setup_complete"
    if pct_exec "$CTID" -- test -f "$marker_file"; then
        log_info "Base OS setup already completed for CTID $CTID. Skipping."
        return 0
    fi

    local essential_packages=("curl" "wget" "vim" "htop" "jq" "git" "rsync" "s-tui" "gnupg" "locales")

    pct_exec "$CTID" -- apt-get update
    pct_exec "$CTID" -- apt-get upgrade -y
    pct_exec "$CTID" -- apt-get install -y "${essential_packages[@]}"

    # Configure locale
    pct_exec "$CTID" -- bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
    pct_exec "$CTID" -- locale-gen
    pct_exec "$CTID" -- update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

    # Create the marker file to signify completion
    pct_exec "$CTID" -- touch "$marker_file"

    log_info "Base OS setup complete for CTID $CTID."
}

# =====================================================================================
# Function: main
# Description: Main entry point for the base setup feature script.
# =====================================================================================
main() {
    parse_arguments "$@"
    perform_base_os_setup
    exit_script 0
}

main "$@"