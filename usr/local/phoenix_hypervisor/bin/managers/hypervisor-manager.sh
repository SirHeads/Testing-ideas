#!/bin/bash
#
# File: hypervisor-manager.sh
# Description: This script is responsible for the initial setup and configuration of the Proxmox hypervisor.
#              It is designed to be called by the central 'phoenix' dispatcher and acts as the dedicated manager
#              for all hypervisor-level operations. The script reads its configuration from a JSON file and
#              executes a series of modular setup scripts in a predefined order to ensure a consistent and
#              reproducible hypervisor environment.
#
#              Key responsibilities include:
#              - Initial system setup (packages, users, etc.).
#              - ZFS storage pool and dataset configuration.
#              - Hardware passthrough setup (VFIO for GPUs).
#              - NVIDIA driver installation and initialization.
#              - Network and firewall configuration.
#              - Shared resource provisioning (NFS, Samba).
#              - AppArmor profile setup and system tuning.
#
# Inputs:
#   --config <path>: (Required) The path to the hypervisor configuration JSON file. This is passed by the 'phoenix' dispatcher.
#   --wipe-disks:    (Optional) A dangerous flag that enables destructive ZFS setup mode. Use with caution. This is passed by the 'phoenix' dispatcher.
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: A library of shared shell functions.
#   - A series of setup scripts located in 'usr/local/phoenix_hypervisor/bin/hypervisor_setup/'.
#
# Version: 1.0.0
# Author: Phoenix Hypervisor Team
#

# --- SCRIPT INITIALIZATION ---
# Determines the absolute directory of the script and the base directory of the Phoenix Hypervisor project.
# This ensures that all paths are relative to the project root, making the system portable.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Script Variables ---
WIPE_DISKS=false # Flag to enable destructive disk operations during ZFS setup.
CONFIG_FILE=""   # Path to the hypervisor configuration file.

# --- SOURCE COMMON UTILITIES ---
# Sources the common utilities script, which provides a centralized library of functions for logging,
# error handling, and other common tasks, ensuring consistency across the system.
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
WIPE_DISKS=false # Flag to enable destructive disk operations during ZFS setup.
CONFIG_FILE=""   # Path to the hypervisor configuration file.

# =====================================================================================
# Function: create_global_symlink
# Description: Creates a symbolic link to the phoenix-global wrapper script in /usr/local/bin,
#              making the 'phoenix' command globally accessible. This function is called at the
#              end of a successful hypervisor setup.
#
# Arguments:
#   None.
#
# Returns:
#   None. The function will call log_fatal and exit if the symlink creation fails.
# =====================================================================================
create_global_symlink() {
    log_info "Creating global symlink for the phoenix command..."
    local source_path="${PHOENIX_BASE_DIR}/bin/phoenix-global"
    local target_path="/usr/local/bin/phoenix"

    if [ -L "$target_path" ]; then
        log_info "Symlink already exists at $target_path. Removing it to ensure it's up-to-date."
        if ! rm "$target_path"; then
            log_fatal "Failed to remove existing symlink at $target_path."
        fi
    fi

    log_info "Creating new symlink from $source_path to $target_path..."
    if ! ln -s "$source_path" "$target_path"; then
        log_fatal "Failed to create symlink. Please ensure you have the necessary permissions."
    fi

    log_info "Phoenix command is now globally accessible."
}

# =====================================================================================
# Function: setup_hypervisor
# Description: Orchestrates the initial setup of the Proxmox hypervisor by executing a
#              predefined sequence of modular setup scripts. This function ensures that all
#              components of the hypervisor are installed and configured in the correct order.
#
# Arguments:
#   $1 - The path to the hypervisor configuration file.
#
# Returns:
#   None. The function will call log_fatal and exit if any of the setup scripts fail.
# =====================================================================================
setup_hypervisor() {
    local config_file="$1"
    log_info "Starting hypervisor setup with config file: $config_file"

    # Validate that the configuration file exists and is readable.
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        log_fatal "Hypervisor setup requires a valid configuration file."
    fi

    # Determine the ZFS setup mode. 'force-destructive' will wipe existing data.
    local zfs_setup_mode="safe"
    if [ "$WIPE_DISKS" = true ]; then
        log_warn "Disk wiping is enabled for this run. ZFS setup will be destructive."
        zfs_setup_mode="force-destructive"
    fi

    # Define the sequence of setup scripts to be executed. The order is critical for proper setup.
    local setup_scripts=(
        "hypervisor_initial_setup.sh"
        "hypervisor_feature_setup_zfs.sh"
        "hypervisor_feature_configure_vfio.sh"
        "hypervisor_feature_install_nvidia.sh"
        "hypervisor_feature_initialize_nvidia_gpus.sh"
        "hypervisor_feature_setup_firewall.sh"
        "hypervisor_feature_setup_nfs.sh"
        "hypervisor_feature_create_heads_user.sh"
        "hypervisor_feature_setup_samba.sh"
        "hypervisor_feature_create_admin_user.sh"
        "hypervisor_feature_provision_shared_resources.sh"
        "hypervisor_feature_setup_apparmor.sh"
        "hypervisor_feature_fix_apparmor_tunables.sh"
    )


    # Iterate through the setup scripts and execute them.
    for script in "${setup_scripts[@]}"; do
        local script_path="${PHOENIX_BASE_DIR}/bin/hypervisor_setup/${script}"
        log_info "Executing setup script: $script..."
        if [ ! -f "$script_path" ]; then
            log_fatal "Hypervisor setup script not found at $script_path."
        fi

        # The ZFS setup script requires special arguments for safety.
        if [[ "$script" == "hypervisor_feature_setup_zfs.sh" ]]; then
            if ! "$script_path" --config "$config_file" --mode "$zfs_setup_mode"; then
                log_fatal "Hypervisor setup script '$script' failed."
            fi
        else
            if ! "$script_path" "$config_file"; then
                log_fatal "Hypervisor setup script '$script' failed."
            fi
        fi
    done

    # Set the hypervisor's DNS to the fallback DNS
    local fallback_dns
    fallback_dns=$(get_global_config_value ".network.fallback_dns")
    if [ -n "$fallback_dns" ]; then
        log_info "Setting hypervisor's DNS to fallback DNS: $fallback_dns"
        echo "nameserver $fallback_dns" > /etc/resolv.conf || log_fatal "Failed to update hypervisor's /etc/resolv.conf."
    fi

    log_info "Hypervisor setup completed successfully."

    # As the final step, create the global symlink to make the phoenix command accessible.
    create_global_symlink
}

# =====================================================================================
# Function: main
# Description: The main entry point for the script. It parses command-line arguments
#              and initiates the hypervisor setup process.
#
# Arguments:
#   $@ - The command-line arguments passed to the script.
#
# Returns:
#   None. Exits with a non-zero status code on error.
# =====================================================================================
main() {
    log_info "Hypervisor manager called with arguments: $@"
    
    # Parse command-line arguments.
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --wipe-disks)
                WIPE_DISKS=true
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Ensure the configuration file path was provided.
    if [ -z "$CONFIG_FILE" ]; then
        log_fatal "Missing required --config argument."
    fi

    # Start the hypervisor setup process.
    setup_hypervisor "$CONFIG_FILE"
}

# --- SCRIPT EXECUTION ---
# Pass all script arguments to the main function.
main "$@"