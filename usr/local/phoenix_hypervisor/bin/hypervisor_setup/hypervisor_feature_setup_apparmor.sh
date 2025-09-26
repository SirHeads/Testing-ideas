#!/bin/bash
#
# File: hypervisor_feature_setup_apparmor.sh
# Description: This script automates the deployment of custom AppArmor profiles
#              for Phoenix Hypervisor LXC containers. It copies all available profiles
#              to the AppArmor directory and reloads the service to apply the changes.
#
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), cp, apparmor_parser, systemctl, diff
# Inputs: None
# Outputs: Log messages to stdout and MAIN_LOG_FILE, exit codes indicating success or failure.
# Version: 1.3.0
# Author: Phoenix Hypervisor Team

# --- Shell Settings ---
set -e
set -o pipefail

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Get the PHOENIX_DIR ---
PHOENIX_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# =====================================================================================
# Function: deploy_apparmor_profiles
# Description: Copies all custom AppArmor profiles to the system directory and reloads AppArmor.
# =====================================================================================
deploy_apparmor_profiles() {
    log_info "Deploying custom AppArmor profiles for Phoenix LXC containers..."

    local source_dir="${PHOENIX_DIR}/etc/apparmor/"
    local dest_dir="/etc/apparmor.d/"
    local profiles_changed=false

    if [ ! -d "$source_dir" ]; then
        log_fatal "AppArmor profiles source directory not found at ${source_dir}."
    fi

    for profile in "${source_dir}"/*; do
        if [ -f "$profile" ]; then
            local profile_name=$(basename "$profile")
            local dest_path

            dest_path="${dest_dir}/${profile_name}"

            if [ ! -f "$dest_path" ] || ! diff -q "$profile" "$dest_path" >/dev/null; then
                log_info "Copying AppArmor file ${profile_name} to ${dest_path}..."
                # Ensure the destination directory exists, especially for tunables
                mkdir -p "$(dirname "$dest_path")"
                cp "$profile" "$dest_path"
                profiles_changed=true
            fi
        fi
    done

    if [ "$profiles_changed" = true ]; then
        log_info "Reloading AppArmor profiles..."
        if systemctl reload apparmor; then
            log_success "AppArmor profiles reloaded successfully."
        else
            log_fatal "Failed to reload AppArmor profiles."
        fi
    else
        log_info "AppArmor profiles are already up-to-date. No changes needed."
    fi
}

# =====================================================================================
# Function: main
# Description: Main entry point for the AppArmor setup script.
# =====================================================================================
main() {
    deploy_apparmor_profiles
    exit_script 0
}

main "$@"