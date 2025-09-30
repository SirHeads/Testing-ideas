#!/bin/bash

# File: hypervisor_feature_setup_apparmor.sh
# Description: This script automates the deployment and enforcement of custom AppArmor profiles on the Proxmox hypervisor.
#              It serves as the single source of truth for ensuring that all AppArmor profiles defined within the
#              Phoenix Hypervisor project are correctly installed and loaded into the kernel. The script iterates
#              through the project's `etc/apparmor/` directory, synchronizes the profile name within each file to match
#              the filename, copies them to the system's `/etc/apparmor.d/` directory, and then loads them.
#              This process is a foundational step in the `--setup-hypervisor` workflow, establishing the security
#              posture of the host before any guest environments are started.
#
# Dependencies:
#   - /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - `apparmor_parser`: The AppArmor utility for loading profiles into the kernel.
#   - `aa-status`: For checking the status of AppArmor.
#   - Standard system utilities: `cp`, `mktemp`, `sed`, `basename`, `rm`.
#
# Inputs:
#   - AppArmor profile files located in `/usr/local/phoenix_hypervisor/etc/apparmor/`.
#
# Outputs:
#   - Copies and sanitizes AppArmor profiles to `/etc/apparmor.d/`.
#   - Creates an AppArmor tunable for nesting at `/etc/apparmor.d/tunables/nesting`.
#   - Loads the AppArmor profiles into the kernel.
#   - Logs its progress, including pre- and post-check status, to standard output.
#   - Exit Code: 0 on success, non-zero on failure.

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
# Description: Copies all custom AppArmor profiles from the project source to the system
#              directory and reloads them into the kernel. It performs a critical synchronization
#              step to ensure the profile name declared inside the file matches the filename.
# =====================================================================================
deploy_apparmor_profiles() {
    log_info "Deploying custom AppArmor profiles for Phoenix LXC containers..."

    local source_dir="${PHOENIX_DIR}/etc/apparmor/"
    local dest_dir="/etc/apparmor.d/"
    local profiles_changed=false

    if [ ! -d "$source_dir" ]; then
        log_fatal "AppArmor profiles source directory not found at ${source_dir}."
    fi

    # This tunable is essential for allowing nested containers (like Docker-in-LXC)
    # to be confined by their own AppArmor profiles.
    log_info "Adding AppArmor nesting tunable for lxc-phoenix-v2..."
    echo '@{apparmor_nesting_profiles} = lxc-phoenix-v2' > /etc/apparmor.d/tunables/nesting

    log_info "--- PRE-CHECK: AppArmor Status ---"
    aa-status || log_warn "Could not retrieve pre-check AppArmor status."
    log_info "------------------------------------"

    # Iterate over every file in the source directory.
    for source_profile in "${source_dir}"/*; do
        if [ -f "$source_profile" ]; then
            local profile_name=$(basename "$source_profile")
            local dest_path="${dest_dir}/${profile_name}"

            # Use a temporary file to avoid modifying the source and to handle potential errors gracefully.
            local temp_profile=$(mktemp)
            cp "$source_profile" "$temp_profile"

            # Dynamically update the profile name in the temporary file to match the filename.
            # This is a crucial step for consistency and prevents "profile not found" errors.
            log_info "Synchronizing profile name in '${profile_name}' to match the filename..."
            # Sanitize the profile name by replacing hyphens with underscores, as hyphens are not valid in profile names.
            local sanitized_profile_name=${profile_name//-/_}
            sed -i "s|^profile .* {|profile ${sanitized_profile_name} {|" "$temp_profile"

            # Copy the sanitized profile to the system's AppArmor directory.
            cp "$temp_profile" "$dest_path"
            rm "$temp_profile" # Clean up the temporary file.

            log_info "Ensuring AppArmor profile '$profile_name' is up-to-date..."

            # To ensure idempotency, first remove the profile from the kernel.
            # This handles cases where the profile was already loaded. Errors are ignored if it doesn't exist.
            apparmor_parser -R "$dest_path" 2>/dev/null || true

            # Now, add (load) the new or updated profile into the kernel.
            if ! apparmor_parser -a "$dest_path"; then
                log_fatal "Failed to load AppArmor profile '$profile_name'. Please check for syntax errors."
            else
                log_info "Successfully loaded AppArmor profile '$profile_name'."
            fi
            profiles_changed=true
        fi
    done

    # After processing all profiles, reload the AppArmor service to ensure all changes are applied system-wide.
    if [ "$profiles_changed" = true ]; then
        log_info "Reloading AppArmor service to apply all profile changes..."
        if ! systemctl reload apparmor; then
            log_fatal "Failed to reload AppArmor service after deploying profiles."
        fi
    else
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