#!/bin/bash

# File: hypervisor_feature_install_nvidia.sh
# Description: This script orchestrates a robust, multi-phase installation of the NVIDIA kernel driver on the Proxmox VE host.
#              As a core component of the hypervisor setup, it ensures that the physical GPUs are managed by the correct proprietary
#              driver, which is a prerequisite for GPU passthrough to LXC containers and VMs. The script is declarative,
#              reading its configuration (driver version, download URL) from the main `phoenix_hypervisor_config.json` file.
#              It is designed to be idempotent, performing checks to see if the correct driver is already installed and functional.
#              A critical aspect of this script is the aggressive cleanup of prior NVIDIA installations to prevent conflicts.
#
# Dependencies:
#   - /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - `jq`: For parsing the JSON configuration file.
#   - `lspci`: To detect if an NVIDIA GPU is present.
#   - `dkms`: For managing kernel modules (specifically for cleanup).
#   - `pve-headers`: The script installs the correct kernel headers for the running Proxmox kernel to build the driver.
#   - `wget`: For downloading the NVIDIA driver runfile.
#
# Inputs:
#   - A path to a JSON configuration file (e.g., `phoenix_hypervisor_config.json`) passed as the first command-line argument.
#   - The JSON file is expected to contain a `.nvidia_driver` object with:
#     - `install`: A boolean (`true` or `false`) to enable or disable the installation.
#     - `version`: The target driver version string (e.g., "550.78").
#     - `runfile_url`: The direct download URL for the NVIDIA `.run` installer file.
#   - An optional `--no-reboot` flag to override the mandatory reboot at the end of the script.
#
# Outputs:
#   - Installs the NVIDIA kernel driver on the Proxmox host.
#   - Blacklists the open-source `nouveau` driver.
#   - Installs `nvtop` for GPU process monitoring.
#   - Logs its progress to standard output.
#   - Triggers a system reboot unless overridden.
#   - Exit Code: 0 on success, non-zero on failure.

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

    # 1.1 Argument Parsing: Expects the config file path and optional --no-reboot flag.
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

    # 1.2 Configuration Loading: Read driver details from the central JSON config.
    log_info "Reading NVIDIA configuration from $HYPERVISOR_CONFIG_FILE..."
    NVIDIA_INSTALL_FLAG=$(jq -r '.nvidia_driver.install // false' "$HYPERVISOR_CONFIG_FILE")
    NVIDIA_DRIVER_VERSION=$(jq -r '.nvidia_driver.version // ""' "$HYPERVISOR_CONFIG_FILE")
    NVIDIA_RUNFILE_URL=$(jq -r '.nvidia_driver.runfile_url // ""' "$HYPERVISOR_CONFIG_FILE")

    # Exit gracefully if installation is disabled in the configuration.
    if [ "$NVIDIA_INSTALL_FLAG" != "true" ]; then
        log_info "NVIDIA driver installation is disabled in configuration. Exiting."
        exit 0
    fi
    # Validate that the required configuration values are present.
    if [ -z "$NVIDIA_DRIVER_VERSION" ] || [ -z "$NVIDIA_RUNFILE_URL" ]; then
        log_fatal "NVIDIA driver version or runfile URL is not specified in the configuration."
    fi
    log_info "Targeting NVIDIA driver version: $NVIDIA_DRIVER_VERSION"

    # 1.3 Hardware Check: Don't attempt installation if no NVIDIA hardware is detected.
    if ! lspci | grep -i nvidia > /dev/null; then
        log_info "No NVIDIA GPU detected. Skipping driver installation."
        exit 0
    fi

    # 1.4 Idempotency Check: Verify if the target driver version is already installed and functional.
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
    # This phase ensures a clean slate by removing any previous NVIDIA driver installations,
    # including packages, kernel modules, and configuration files, to prevent conflicts.
    log_info "--- Phase 2: Aggressive Cleanup ---"
    rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true
    apt-get purge -y '*nvidia*' &>/dev/null || log_fatal "Failed to purge NVIDIA packages."
    apt-get autoremove -y &>/dev/null
    # Robustly remove any existing NVIDIA DKMS modules.
    dkms status | grep 'nvidia' || true | while read -r line; do
        local module_info
        module_info=$(echo "$line" | awk -F', ' '{print $1 "/" $2}')
        dkms remove "$module_info" --all || log_warn "Failed to remove DKMS module $module_info."
    done
    rm -rf /etc/modprobe.d/nvidia* /etc/X11/xorg.conf

    # --- Phase 3: System Preparation ---
    # Install the necessary packages to build the NVIDIA kernel module against the current Proxmox kernel.
    log_info "--- Phase 3: System Preparation ---"
    local current_kernel_version
    current_kernel_version=$(uname -r)
    local pve_headers_package="pve-headers-${current_kernel_version}"
    retry_command "apt-get update" || log_fatal "Failed to update package lists."
    retry_command "apt-get install -y ${pve_headers_package} build-essential dkms pkg-config wget" || log_fatal "Failed to install essential dependencies."

    # --- Phase 4: Driver Installation ---
    log_info "--- Phase 4: Driver Installation ---"
    # Blacklist the nouveau driver to prevent it from interfering with the NVIDIA driver.
    cat << EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF
    update-initramfs -u || log_warn "Failed to update initramfs."
    
    # Download the NVIDIA runfile from the URL specified in the config, using a local cache.
    local runfile_path
    runfile_path=$(cache_and_get_file "$NVIDIA_RUNFILE_URL" "$CACHE_DIR") || log_fatal "Failed to cache NVIDIA driver runfile."
    
    chmod +x "$runfile_path"
    # Execute the installer silently.
    # CRITICAL: --no-dkms is used. This means the driver is built only for the current kernel.
    # If the kernel is updated, this script MUST be re-run to rebuild and reinstall the driver.
    "$runfile_path" --silent --no-x-check --no-nouveau-check --no-opengl-files --accept-license --no-dkms || log_fatal "NVIDIA driver installation failed."

    # --- Phase 5: Finalization & Reboot ---
    log_info "--- Phase 5: Finalization & Reboot ---"
    log_info "Updating kernel module dependencies..."
    depmod -a || log_warn "depmod -a failed, but continuing."
    # Install nvtop, a useful tool for monitoring GPU processes and utilization.
    log_info "Installing nvtop..."
    apt-get install -y nvtop
    
    # A reboot is mandatory to properly load the new kernel module.
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