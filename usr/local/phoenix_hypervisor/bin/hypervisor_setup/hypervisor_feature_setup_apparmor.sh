#!/bin/bash
#
# File: hypervisor_feature_setup_apparmor.sh
# Description: This script automates the deployment of custom AppArmor profiles
#              for Phoenix Hypervisor LXC containers. It copies all available profiles
#              to the AppArmor directory and reloads them individually.
#
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), cp, apparmor_parser, diff
# Inputs: None
# Outputs: Log messages to stdout and MAIN_LOG_FILE, exit codes indicating success or failure.
# Version: 1.4.0
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
# Description: Copies all custom AppArmor profiles to the system directory and reloads them.
# =====================================================================================
deploy_apparmor_profiles() {
    log_info "Deploying custom AppArmor profiles for Phoenix LXC containers..."

    local source_dir="${PHOENIX_DIR}/etc/apparmor/"
    local dest_dir="/etc/apparmor.d/"
    local profiles_changed=false

    if [ ! -d "$source_dir" ]; then
        log_fatal "AppArmor profiles source directory not found at ${source_dir}."
    fi

    log_info "--- PRE-CHECK: AppArmor Status ---"
    aa-status || log_warn "Could not retrieve pre-check AppArmor status."
    log_info "------------------------------------"

    for source_profile in "${source_dir}"/*; do
        if [ -f "$source_profile" ]; then
            local profile_name=$(basename "$source_profile")
            local dest_path="${dest_dir}/${profile_name}"

            # Create a temporary file for modifications
            local temp_profile=$(mktemp)
            cp "$source_profile" "$temp_profile"

            # Dynamically update the profile name in the temporary file to match the filename.
            # This ensures the profile name is always in sync with the file that defines it.
            log_info "Synchronizing profile name in '${profile_name}' to match the filename..."
            # Sanitize the profile name by replacing hyphens with underscores
            local sanitized_profile_name=${profile_name//-/_}
            sed -i "s|^profile .* {|profile ${sanitized_profile_name} {|" "$temp_profile"

            # Copy the modified profile to the destination
            cp "$temp_profile" "$dest_path"
            rm "$temp_profile" # Clean up the temporary file

            # Reload the profile using apparmor_parser with the --replace flag
            log_info "Ensuring AppArmor profile '$profile_name' is up-to-date..."

            # Remove the profile first to ensure idempotency.
            # We redirect stderr to /dev/null and use '|| true' to ignore errors if the profile doesn't exist.
            apparmor_parser -R "$dest_path" 2>/dev/null || true

            # Now, add the profile.
            if ! apparmor_parser -a "$dest_path"; then
                log_fatal "Failed to load AppArmor profile '$profile_name'. Please check for syntax errors."
            else
                log_info "Successfully loaded AppArmor profile '$profile_name'."
            fi
            profiles_changed=true
        fi
    done

    if [ "$profiles_changed" = false ]; then
        log_info "No AppArmor profiles found to deploy."
    fi

    log_info "--- POST-CHECK: AppArmor Status ---"
    aa-status || log_warn "Could not retrieve post-check AppArmor status."
    log_info "-------------------------------------"
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