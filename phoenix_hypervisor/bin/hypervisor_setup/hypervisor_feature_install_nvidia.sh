#!/bin/bash

# File: hypervisor_feature_install_nvidia.sh
# Description: Installs and configures NVIDIA drivers and associated tools (like nvtop)
#              on a Proxmox VE host. It reads configuration from `hypervisor_config.json`,
#              handles driver cleanup, dependency installation, kernel module management
#              via DKMS, and verifies the installation. A system reboot is strongly recommended.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq, lspci, nvidia-smi,
#               nvidia-uninstall (if present), apt-get, dkms, pkg-config, g++, freeglut3-dev,
#               libx11-dev, libxmu-dev, libxi-dev, libglu1-mesa-dev, libfreeimage-dev,
#               libglfw3-dev, wget, htop, btop, nvtop, glances, git, pciutils, cmake,
#               curl, libcurl4-openssl-dev, make, rmmod, modprobe, update-initramfs.
# Inputs:
#   --no-reboot: Optional flag to skip the automatic reboot after installation.
#   Configuration values from HYPERVISOR_CONFIG_FILE: .nvidia_driver.install,
#   .nvidia_driver.version, .nvidia_driver.runfile_url.
# Outputs:
#   NVIDIA driver installation logs, package installation outputs, kernel module
#   status, nvidia-smi output, log messages to stdout and MAIN_LOG_FILE,
#   exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# Source common utilities
source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh

# Ensure script is run as root
check_root

log_info "Starting NVIDIA driver installation."

# Parse command-line arguments
# =====================================================================================
# Function: parse_arguments
# Description: Parses command-line arguments for the NVIDIA driver installation script.
#              Currently supports a `--no-reboot` flag.
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   None. Exits with a fatal error if an unknown option is encountered.
# =====================================================================================
parse_arguments() {
    NO_REBOOT=0 # Initialize NO_REBOOT flag
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-reboot)
                NO_REBOOT=1 # Set flag to skip reboot
                shift
                ;;
            *)
                log_fatal "Unknown option $1" # Handle unknown options
                ;;
        esac
    done
}

# Read NVIDIA configuration from hypervisor_config.json
log_info "Reading NVIDIA configuration from $HYPERVISOR_CONFIG_FILE..."
# Read NVIDIA configuration from hypervisor_config.json
log_info "Reading NVIDIA configuration from $HYPERVISOR_CONFIG_FILE..."
NVIDIA_INSTALL_FLAG=$(jq -r '.nvidia_driver.install // false' "$HYPERVISOR_CONFIG_FILE") # Flag to enable/disable NVIDIA driver installation
NVIDIA_DRIVER_VERSION=$(jq -r '.nvidia_driver.version // "580.76.05"' "$HYPERVISOR_CONFIG_FILE") # Desired NVIDIA driver version
NVIDIA_RUNFILE_URL=$(jq -r '.nvidia_driver.runfile_url // "https://us.download.nvidia.com/XFree86/Linux-x86_64/580.76.05/NVIDIA-Linux-x86_64-580.76.05.run"' "$HYPERVISOR_CONFIG_FILE") # URL for the NVIDIA driver runfile

# If NVIDIA driver installation is disabled in the configuration, exit
if [ "$NVIDIA_INSTALL_FLAG" != "true" ]; then
    log_info "NVIDIA driver installation is disabled in configuration. Skipping."
    exit 0
fi

log_info "Targeting NVIDIA driver version: $NVIDIA_DRIVER_VERSION"
log_info "Using download URL: $NVIDIA_RUNFILE_URL"

# Check for NVIDIA GPU
# Check for NVIDIA GPU presence using lspci
if ! lspci | grep -i nvidia > /dev/null; then
    log_info "No NVIDIA GPU detected. Skipping driver installation."
    exit 0
fi

# --- Enhanced Function to Install NVIDIA Driver ---
# =====================================================================================
# Function: install_nvidia_driver
# Description: Handles the complete installation process for NVIDIA drivers.
#              This includes checking existing installations, cleaning up old drivers,
#              installing prerequisites, blacklisting nouveau, downloading and
#              executing the NVIDIA runfile, and performing post-installation steps
#              like DKMS integration and module loading.
# Arguments:
#   None (uses global NVIDIA_DRIVER_VERSION, NVIDIA_RUNFILE_URL).
# Returns:
#   0 on successful driver installation and verification, 1 on failure.
# =====================================================================================
install_nvidia_driver() {
    local driver_version="$NVIDIA_DRIVER_VERSION" # Target NVIDIA driver version
    local runfile="NVIDIA-Linux-x86_64-${driver_version}.run" # Name of the driver runfile
    local download_url="$NVIDIA_RUNFILE_URL" # URL to download the driver runfile
    local current_kernel_version # Current running kernel version
    current_kernel_version=$(uname -r)
    local pve_headers_package="pve-headers-${current_kernel_version}" # Name of PVE kernel headers package

    log_info "Current running kernel version: $current_kernel_version"

    # Check if NVIDIA driver is already installed with correct version
    # Check if NVIDIA driver is already installed and matches the target version
    if command -v nvidia-smi >/dev/null 2>&1; then
        installed_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null | head -n 1) # Get installed driver version
        if [[ "$installed_version" == "$driver_version" ]]; then
            log_info "NVIDIA driver version ${driver_version} already installed."

            # Check if NVIDIA kernel module is loaded and DKMS status
            if lsmod | grep -q nvidia; then
                log_info "NVIDIA kernel module is loaded for the current kernel ($current_kernel_version)."
                local dkms_status_line # Variable to store DKMS status line
                dkms_status_line=$(dkms status | grep "^nvidia/${driver_version}," | grep "$current_kernel_version" || true) # Get DKMS status for NVIDIA module
                if echo "$dkms_status_line" | grep -q "installed"; then
                    log_info "NVIDIA DKMS module is installed for the current kernel ($current_kernel_version)."
                    log_info "Driver $driver_version is correctly installed and active for the current kernel."
                    return 0 # Exit if driver is already correctly installed and active
                elif echo "$dkms_status_line" | grep -q "built"; then
                    log_warn "NVIDIA DKMS module is built but not installed for the current kernel ($current_kernel_version). Attempting to install..."
                    if dkms install "nvidia/${driver_version}" -k "${current_kernel_version}"; then
                         log_info "Successfully installed NVIDIA DKMS module for the current kernel ($current_kernel_version)."
                    else
                         log_error "Failed to install NVIDIA DKMS module for the current kernel ($current_kernel_version). Proceeding with fresh installation."
                    fi
                else
                     log_info "NVIDIA DKMS status unclear for current kernel ($current_kernel_version). Proceeding with fresh installation check."
                fi
            else
                log_info "NVIDIA driver $driver_version found, but kernel module is not loaded. Proceeding with installation check/reinstall."
            fi
        else
             log_info "NVIDIA driver version ${installed_version} found, but ${driver_version} is required. Proceeding with installation."
        fi
    fi

    # --- Clean up any existing NVIDIA driver installations ---
    # Clean up any existing NVIDIA driver installations to ensure a clean install
    log_info "Cleaning up existing NVIDIA driver installations..."
    if command -v nvidia-uninstall >/dev/null 2>&1; then
        nvidia-uninstall --silent || log_warn "Failed to run nvidia-uninstall, continuing." # Run NVIDIA uninstaller
    fi
    apt-get purge -y '~nvidia' || log_warn "Failed to purge NVIDIA packages, continuing." # Purge NVIDIA related packages
    if dkms status | grep -q "nvidia/${driver_version}"; then
        log_info "Removing old NVIDIA DKMS modules..."
        dkms remove "nvidia/${driver_version}" --all || log_warn "Failed to remove old NVIDIA DKMS modules, continuing." # Remove old DKMS modules
    fi

    # --- Install Project-Required Prerequisites ---
    # Install project-required prerequisites, build tools, and kernel headers
    log_info "Installing project-required build dependencies, tools, and kernel headers..."
    retry_command "apt-get update" || log_fatal "Failed to update package lists"
    retry_command "apt-get install -y ${pve_headers_package} build-essential dkms pkg-config" || log_fatal "Failed to install essential kernel headers/build tools"
    retry_command "apt-get install -y g++ freeglut3-dev libx11-dev libxmu-dev libxi-dev libglu1-mesa-dev libfreeimage-dev libglfw3-dev wget htop btop nvtop glances git pciutils cmake curl libcurl4-openssl-dev make" || log_fatal "Failed to install project-required dependencies"

    # Blacklist nouveau
    # Blacklist the nouveau open-source NVIDIA driver to prevent conflicts
    log_info "Blacklisting nouveau driver..."
    cat << EOF > /etc/modprobe.d/blacklist-nouveau.conf # Create blacklist file
blacklist nouveau
options nouveau modeset=0
EOF

    # Download and install NVIDIA driver
    # Download the NVIDIA driver runfile
    log_info "Downloading NVIDIA driver ${driver_version}..."
    if ! wget --quiet "$download_url" -O "$runfile"; then
        log_fatal "Failed to download NVIDIA driver runfile from $download_url."
    fi

    # Install the NVIDIA driver using the downloaded runfile
    log_info "Installing NVIDIA driver ${driver_version}..."
    chmod +x "$runfile" # Make the runfile executable
    if ! ./"$runfile" --silent --no-x-check --accept-license; then # Execute the runfile silently
        log_error "NVIDIA driver installation failed."
        rm -f "$runfile" # Clean up runfile on failure
        return 1
    fi

    # --- Enhanced Post-Installation Steps for Kernel Module Robustness ---
    # Perform enhanced post-installation steps for kernel module robustness and DKMS integration
    log_info "Performing enhanced post-installation steps for kernel module robustness..."

    # Ensure PVE kernel headers are installed and up-to-date
    if ! dpkg -l | grep -q "^ii.*${pve_headers_package}"; then
        log_info "Installing/updating PVE kernel headers package: ${pve_headers_package}..."
        if ! apt-get install -y "${pve_headers_package}"; then
             log_error "Failed to install PVE kernel headers ${pve_headers_package}. DKMS build will likely fail."
             rm -f "$runfile"
             return 1
        fi
    else
        log_info "PVE kernel headers package ${pve_headers_package} is already installed and correct."
    fi

    # Force DKMS to build and install the NVIDIA module for the current kernel
    log_info "Forcing DKMS to build/install NVIDIA module for the current kernel (${current_kernel_version})..."
    dkms remove "nvidia/${driver_version}" -k "${current_kernel_version}" --all 2>/dev/null || true # Remove any existing DKMS modules
    if ! dkms add "nvidia/${driver_version}"; then
         log_warn "Failed to add NVIDIA module source to DKMS. It might already be added."
    fi
    if ! dkms install "nvidia/${driver_version}" -k "${current_kernel_version}"; then
        log_error "Failed to build/install NVIDIA module via DKMS for kernel ${current_kernel_version}."
        rm -f "$runfile"
        return 1
    fi
    log_info "DKMS build/install for NVIDIA module completed successfully for kernel ${current_kernel_version}."

    # Load the NVIDIA kernel module
    log_info "Loading NVIDIA kernel module..."
    rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true # Unload existing modules if present
    if ! modprobe nvidia; then # Load the NVIDIA module
        log_error "Failed to load NVIDIA kernel module."
        rm -f "$runfile"
        return 1
    fi
    log_info "NVIDIA kernel module loaded successfully."
    # --- End Enhanced Post-Installation Steps ---

    # Update initramfs to include the blacklist and any necessary modules
    # Update initramfs to include the nouveau blacklist and any necessary modules
    log_info "Updating initramfs to incorporate changes..."
    if ! update-initramfs -u; then
        log_warn "Failed to update initramfs. Continuing, but consider running 'update-initramfs -u' manually after."
    fi

    rm -f "$runfile"

    # Verify installation
    # Verify NVIDIA module is loaded
    if ! lsmod | grep -q nvidia; then
        log_error "NVIDIA module not loaded after post-install steps."
        return 1
    fi

    # Verify nvidia-smi command is available
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        log_error "nvidia-smi not found after installation and module loading."
        return 1
    fi

    local nvidia_smi_output # Variable to store nvidia-smi output
    nvidia_smi_output=$(nvidia-smi 2>&1) || { log_error "nvidia-smi command failed."; return 1; } # Run nvidia-smi
    local installed_drv_version # Variable to store installed driver version
    installed_drv_version=$(echo "$nvidia_smi_output" | grep "Driver Version" | awk '{print $3}') # Extract driver version
    if [[ "$installed_drv_version" != "$driver_version" ]]; then
         log_error "Driver version mismatch after installation. Expected $driver_version, got $installed_drv_version."
         return 1
    fi
    log_info "NVIDIA driver ${driver_version} installed and verified successfully."
    log_info "nvidia-smi output:"
    log_plain_output <<< "$nvidia_smi_output" # Log nvidia-smi output
    return 0
}

# Function to install nvtop
# =====================================================================================
# Function: install_nvtop
# Description: Installs the `nvtop` utility for monitoring NVIDIA GPU usage.
# Arguments:
#   None.
# Returns:
#   0 on successful installation and verification, 1 on failure.
# =====================================================================================
install_nvtop() {
    log_info "Installing nvtop..."
    retry_command "apt-get install -y nvtop" || log_warn "Failed to install nvtop, but continuing." # Install nvtop
    # Verify nvtop installation
    if command -v nvtop >/dev/null 2>&1; then
        log_info "nvtop installed successfully."
    else
        log_warn "Failed to verify nvtop installation."
        return 1
    fi
    return 0
}

# Main execution
# =====================================================================================
# Function: main
# Description: Main execution flow for the NVIDIA driver installation script.
#              It orchestrates the installation of NVIDIA drivers and nvtop,
#              and handles post-installation recommendations like rebooting.
# Arguments:
#   None (uses global NVIDIA_DRIVER_VERSION, NO_REBOOT).
# Returns:
#   Exits with status 0 on successful completion, or a fatal error on critical failure.
# =====================================================================================
main() {
    log_info "Starting NVIDIA driver (${NVIDIA_DRIVER_VERSION}) and nvtop installation..."

    local driver_installed=0 # Flag to track if driver installation was successful
    if install_nvidia_driver; then # Attempt to install NVIDIA driver
        driver_installed=1
    else
        log_fatal "Failed to install NVIDIA driver version ${NVIDIA_DRIVER_VERSION}."
    fi

install_nvtop # Install nvtop utility

    # Provide post-installation instructions and handle reboot
    if [[ "$driver_installed" -eq 1 ]]; then
        log_info "NVIDIA driver (${NVIDIA_DRIVER_VERSION}) installation and post-install steps completed successfully."
        log_info "A reboot is STRONGLY RECOMMENDED to ensure stability, proper DKMS integration, and initramfs updates take full effect."
        if [[ "$NO_REBOOT" -eq 0 ]]; then
            log_info "Rebooting system in 15 seconds. Press Ctrl+C to cancel."
            sleep 15 # Wait for 15 seconds before rebooting
            reboot # Initiate system reboot
        else
            log_info "Reboot skipped due to --no-reboot flag. Please reboot manually as soon as possible to apply all changes and ensure stability."
        fi
    fi
    
    log_info "NVIDIA driver (${NVIDIA_DRIVER_VERSION}) and tools installation completed successfully."
    exit 0
}

parse_arguments "$@" # Parse arguments before main execution
main "$@" # Call the main function with all arguments

log_info "NVIDIA driver (${NVIDIA_DRIVER_VERSION}) and tools installation completed successfully."
exit 0