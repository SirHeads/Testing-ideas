#!/bin/bash

# File: hypervisor_feature_install_nvidia.sh
# Description: Implements a robust, single-pass installation of NVIDIA drivers on a Proxmox VE host.
#              This script is designed to be idempotent and resilient, handling partial or failed
#              previous installations. It concludes with a mandatory reboot.
#
# Version: 6.0.0
# Author: Phoenix Hypervisor Team

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# Ensure script is run as root
check_root

# --- Global Variables ---
HYPERVISOR_CONFIG_FILE=""
NO_REBOOT_OVERRIDE=0
SCRIPT_VERSION="6.0.0"
CACHE_DIR="/usr/local/phoenix_hypervisor/cache"

# =====================================================================================
# Main Execution Logic
# =====================================================================================
main() {
    log_info "Starting NVIDIA driver installation (Version: $SCRIPT_VERSION)"

    # --- Phase 1: Pre-flight Checks & Configuration ---
    log_info "--- Phase 1: Pre-flight Checks & Configuration ---"

    # 1.1 Argument Parsing
    if [ -z "$1" ]; then
        log_fatal "Configuration file path not provided."
    fi
    HYPERVISOR_CONFIG_FILE="$1"
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-reboot)
                NO_REBOOT_OVERRIDE=1
                log_warn "User specified --no-reboot. This overrides the mandatory reboot."
                shift
                ;;
            *)
                log_fatal "Unknown option $1"
                ;;
        esac
    done

    # 1.2 Configuration Loading
    log_info "Reading NVIDIA configuration from $HYPERVISOR_CONFIG_FILE..."
    NVIDIA_INSTALL_FLAG=$(jq -r '.nvidia_driver.install // false' "$HYPERVISOR_CONFIG_FILE")
    NVIDIA_DRIVER_VERSION=$(jq -r '.nvidia_driver.version // ""' "$HYPERVISOR_CONFIG_FILE")
    NVIDIA_RUNFILE_URL=$(jq -r '.nvidia_driver.runfile_url // ""' "$HYPERVISOR_CONFIG_FILE")

    if [ "$NVIDIA_INSTALL_FLAG" != "true" ]; then
        log_info "NVIDIA driver installation is disabled in configuration. Exiting."
        exit 0
    fi
    if [ -z "$NVIDIA_DRIVER_VERSION" ] || [ -z "$NVIDIA_RUNFILE_URL" ]; then
        log_fatal "NVIDIA driver version or runfile URL is not specified in the configuration."
    fi
    log_info "Targeting NVIDIA driver version: $NVIDIA_DRIVER_VERSION"

    # 1.3 Hardware Check
    if ! lspci | grep -i nvidia > /dev/null; then
        log_info "No NVIDIA GPU detected. Skipping driver installation."
        exit 0
    fi

    # 1.4 Idempotency Check
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        local installed_version
        installed_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null | head -n 1)
        if [[ "$installed_version" == "$NVIDIA_DRIVER_VERSION" ]]; then
            log_info "NVIDIA driver version ${NVIDIA_DRIVER_VERSION} is already installed and verified. Exiting."
            exit 0
        else
            log_info "An existing NVIDIA driver (version ${installed_version}) was found, but it does not match the target version ${NVIDIA_DRIVER_VERSION}. Proceeding with re-installation."
        fi
    else
        log_info "A complete and functional NVIDIA driver installation was not detected. Proceeding with installation."
    fi

    # --- Phase 2: Aggressive Cleanup ---
    log_info "--- Phase 2: Aggressive Cleanup ---"
    rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true
    apt-get purge -y '*nvidia*' &>/dev/null || log_fatal "Failed to purge NVIDIA packages."
    apt-get autoremove -y &>/dev/null
    # The DKMS removal logic is now more robust
    dkms status | grep 'nvidia' || true | while read -r line; do
        local module_info
        module_info=$(echo "$line" | awk -F', ' '{print $1 "/" $2}')
        dkms remove "$module_info" --all || log_warn "Failed to remove DKMS module $module_info."
    done
    rm -rf /etc/modprobe.d/nvidia* /etc/X11/xorg.conf

    # --- Phase 3: System Preparation ---
    log_info "--- Phase 3: System Preparation ---"
    local current_kernel_version
    current_kernel_version=$(uname -r)
    local pve_headers_package="pve-headers-${current_kernel_version}"
    retry_command "apt-get update" || log_fatal "Failed to update package lists."
    retry_command "apt-get install -y ${pve_headers_package} build-essential dkms pkg-config wget" || log_fatal "Failed to install essential dependencies."

    # --- Phase 4: Driver Installation ---
    log_info "--- Phase 4: Driver Installation ---"
    cat << EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF
    update-initramfs -u || log_warn "Failed to update initramfs."
    
    local runfile_path
    runfile_path=$(cache_and_get_file "$NVIDIA_RUNFILE_URL" "$CACHE_DIR") || log_fatal "Failed to cache NVIDIA driver runfile."
    
    chmod +x "$runfile_path"
    "$runfile_path" --silent --no-x-check --no-nouveau-check --no-opengl-files --accept-license --no-dkms || log_fatal "NVIDIA driver installation failed."

    # --- Phase 5: Finalization & Reboot ---
    log_info "--- Phase 5: Finalization & Reboot ---"
    log_info "Updating kernel module dependencies..."
    depmod -a || log_warn "depmod -a failed, but continuing."
# Install nvtop for GPU process monitoring
log_info "Installing nvtop..."
apt-get install -y nvtop
    
    if [[ "$NO_REBOOT_OVERRIDE" -eq 0 ]]; then
        log_info "System preparation complete. Rebooting now to load the new driver."
        reboot
    else
        log_warn "Reboot override is active. Please reboot manually to complete the installation."
    fi

    log_info "NVIDIA driver installation script finished."
    exit 0
}

# Run the main function with all script arguments
main "$@"