#!/bin/bash

# File: hypervisor_feature_install_nvidia.sh
# Description: Installs NVIDIA drivers on Proxmox VE, reading configuration from hypervisor_config.json.
# Version: 1.0.0
# Author: Roo (AI Architect)

# Source common utilities
source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh

# Ensure script is run as root
check_root

log_info "Starting NVIDIA driver installation."

# Parse command-line arguments
NO_REBOOT=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-reboot)
            NO_REBOOT=1
            shift
            ;;
        *)
            log_fatal "Unknown option $1"
            ;;
    esac
done

# Read NVIDIA configuration from hypervisor_config.json
log_info "Reading NVIDIA configuration from $HYPERVISOR_CONFIG_FILE..."
NVIDIA_INSTALL_FLAG=$(jq -r '.nvidia_driver.install // false' "$HYPERVISOR_CONFIG_FILE")
NVIDIA_DRIVER_VERSION=$(jq -r '.nvidia_driver.version // "580.76.05"' "$HYPERVISOR_CONFIG_FILE")
NVIDIA_RUNFILE_URL=$(jq -r '.nvidia_driver.runfile_url // "https://us.download.nvidia.com/XFree86/Linux-x86_64/580.76.05/NVIDIA-Linux-x86_64-580.76.05.run"' "$HYPERVISOR_CONFIG_FILE")

if [ "$NVIDIA_INSTALL_FLAG" != "true" ]; then
    log_info "NVIDIA driver installation is disabled in configuration. Skipping."
    exit 0
fi

log_info "Targeting NVIDIA driver version: $NVIDIA_DRIVER_VERSION"
log_info "Using download URL: $NVIDIA_RUNFILE_URL"

# Check for NVIDIA GPU
if ! lspci | grep -i nvidia > /dev/null; then
    log_info "No NVIDIA GPU detected. Skipping driver installation."
    exit 0
fi

# --- Enhanced Function to Install NVIDIA Driver ---
install_nvidia_driver() {
    local driver_version="$NVIDIA_DRIVER_VERSION"
    local runfile="NVIDIA-Linux-x86_64-${driver_version}.run"
    local download_url="$NVIDIA_RUNFILE_URL"
    local current_kernel_version
    current_kernel_version=$(uname -r)
    local pve_headers_package="pve-headers-${current_kernel_version}"

    log_info "Current running kernel version: $current_kernel_version"

    # Check if NVIDIA driver is already installed with correct version
    if command -v nvidia-smi >/dev/null 2>&1; then
        installed_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null | head -n 1)
        if [[ "$installed_version" == "$driver_version" ]]; then
            log_info "NVIDIA driver version ${driver_version} already installed."

            if lsmod | grep -q nvidia; then
                log_info "NVIDIA kernel module is loaded for the current kernel ($current_kernel_version)."
                local dkms_status_line
                dkms_status_line=$(dkms status | grep "^nvidia/${driver_version}," | grep "$current_kernel_version" || true)
                if echo "$dkms_status_line" | grep -q "installed"; then
                    log_info "NVIDIA DKMS module is installed for the current kernel ($current_kernel_version)."
                    log_info "Driver $driver_version is correctly installed and active for the current kernel."
                    return 0
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
    log_info "Cleaning up existing NVIDIA driver installations..."
    if command -v nvidia-uninstall >/dev/null 2>&1; then
        nvidia-uninstall --silent || log_warn "Failed to run nvidia-uninstall, continuing."
    fi
    apt-get purge -y '~nvidia' || log_warn "Failed to purge NVIDIA packages, continuing."
    if dkms status | grep -q "nvidia/${driver_version}"; then
        log_info "Removing old NVIDIA DKMS modules..."
        dkms remove "nvidia/${driver_version}" --all || log_warn "Failed to remove old NVIDIA DKMS modules, continuing."
    fi

    # --- Install Project-Required Prerequisites ---
    log_info "Installing project-required build dependencies, tools, and kernel headers..."
    retry_command "apt-get update" || log_fatal "Failed to update package lists"
    retry_command "apt-get install -y ${pve_headers_package} build-essential dkms pkg-config" || log_fatal "Failed to install essential kernel headers/build tools"
    retry_command "apt-get install -y g++ freeglut3-dev libx11-dev libxmu-dev libxi-dev libglu1-mesa-dev libfreeimage-dev libglfw3-dev wget htop btop nvtop glances git pciutils cmake curl libcurl4-openssl-dev make" || log_fatal "Failed to install project-required dependencies"

    # Blacklist nouveau
    log_info "Blacklisting nouveau driver..."
    cat << EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF

    # Download and install NVIDIA driver
    log_info "Downloading NVIDIA driver ${driver_version}..."
    if ! wget --quiet "$download_url" -O "$runfile"; then
        log_fatal "Failed to download NVIDIA driver runfile from $download_url."
    fi

    log_info "Installing NVIDIA driver ${driver_version}..."
    chmod +x "$runfile"
    if ! ./"$runfile" --silent --no-x-check --accept-license; then
        log_error "NVIDIA driver installation failed."
        rm -f "$runfile"
        return 1
    fi

    # --- Enhanced Post-Installation Steps for Kernel Module Robustness ---
    log_info "Performing enhanced post-installation steps for kernel module robustness..."

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

    log_info "Forcing DKMS to build/install NVIDIA module for the current kernel (${current_kernel_version})..."
    dkms remove "nvidia/${driver_version}" -k "${current_kernel_version}" --all 2>/dev/null || true
    if ! dkms add "nvidia/${driver_version}"; then
         log_warn "Failed to add NVIDIA module source to DKMS. It might already be added."
    fi
    if ! dkms install "nvidia/${driver_version}" -k "${current_kernel_version}"; then
        log_error "Failed to build/install NVIDIA module via DKMS for kernel ${current_kernel_version}."
        rm -f "$runfile"
        return 1
    fi
    log_info "DKMS build/install for NVIDIA module completed successfully for kernel ${current_kernel_version}."

    log_info "Loading NVIDIA kernel module..."
    rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true
    if ! modprobe nvidia; then
        log_error "Failed to load NVIDIA kernel module."
        rm -f "$runfile"
        return 1
    fi
    log_info "NVIDIA kernel module loaded successfully."
    # --- End Enhanced Post-Installation Steps ---

    # Update initramfs to include the blacklist and any necessary modules
    log_info "Updating initramfs to incorporate changes..."
    if ! update-initramfs -u; then
        log_warn "Failed to update initramfs. Continuing, but consider running 'update-initramfs -u' manually after."
    fi

    rm -f "$runfile"

    # Verify installation
    if ! lsmod | grep -q nvidia; then
        log_error "NVIDIA module not loaded after post-install steps."
        return 1
    fi

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        log_error "nvidia-smi not found after installation and module loading."
        return 1
    fi

    local nvidia_smi_output
    nvidia_smi_output=$(nvidia-smi 2>&1) || { log_error "nvidia-smi command failed."; return 1; }
    local installed_drv_version
    installed_drv_version=$(echo "$nvidia_smi_output" | grep "Driver Version" | awk '{print $3}')
    if [[ "$installed_drv_version" != "$driver_version" ]]; then
         log_error "Driver version mismatch after installation. Expected $driver_version, got $installed_drv_version."
         return 1
    fi
    log_info "NVIDIA driver ${driver_version} installed and verified successfully."
    log_info "nvidia-smi output:"
    log_plain_output <<< "$nvidia_smi_output"
    return 0
}

# Function to install nvtop
install_nvtop() {
    log_info "Installing nvtop..."
    retry_command "apt-get install -y nvtop" || log_warn "Failed to install nvtop, but continuing."
    if command -v nvtop >/dev/null 2>&1; then
        log_info "nvtop installed successfully."
    else
        log_warn "Failed to verify nvtop installation."
        return 1
    fi
    return 0
}

# Main execution
log_info "Starting NVIDIA driver (${NVIDIA_DRIVER_VERSION}) and nvtop installation..."

driver_installed=0
if install_nvidia_driver; then
    driver_installed=1
else
    log_fatal "Failed to install NVIDIA driver version ${NVIDIA_DRIVER_VERSION}."
fi

install_nvtop

if [[ "$driver_installed" -eq 1 ]]; then
    log_info "NVIDIA driver (${NVIDIA_DRIVER_VERSION}) installation and post-install steps completed successfully."
    log_info "A reboot is STRONGLY RECOMMENDED to ensure stability, proper DKMS integration, and initramfs updates take full effect."
    if [[ "$NO_REBOOT" -eq 0 ]]; then
        log_info "Rebooting system in 15 seconds. Press Ctrl+C to cancel."
        sleep 15
        reboot
    else
        log_info "Reboot skipped due to --no-reboot flag. Please reboot manually as soon as possible to apply all changes and ensure stability."
    fi
fi

log_info "NVIDIA driver (${NVIDIA_DRIVER_VERSION}) and tools installation completed successfully."
exit 0