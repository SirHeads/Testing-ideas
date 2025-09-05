#!/bin/bash
# phoenix_install_nvidia_driver.sh
# Installs NVIDIA drivers on Proxmox VE
# Version: 1.0.14 (Updated for Driver 580.76.05, Prerequisites, and Robust Kernel Handling)
# Author: Heads, Grok, Devstral, Assistant
# Usage: ./phoenix_install_nvidia_driver.sh [--no-reboot]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup
# Meta {"chunk_id": "phoenix_install_nvidia_driver-1.0", "keywords": ["nvidia", "driver", "proxmox"], "comment_type": "block"}

# Main: Installs and configures NVIDIA drivers for Proxmox VE
# Args: [--no-reboot] (optional)
# Returns: 0 on success, 1 on failure
# Meta {"chunk_id": "phoenix_install_nvidia_driver-1.14", "keywords": ["nvidia", "driver", "proxmox"], "comment_type": "block"}
# Algorithm: NVIDIA driver installation orchestration
# Checks prerequisites, installs drivers, updates initramfs, verifies installation, ensures kernel module correctness
# Keywords: [nvidia, driver, proxmox]

# Fallback logging function if common.sh doesn't provide log_message
# Meta {"chunk_id": "phoenix_install_nvidia_driver-1.2", "keywords": ["logging"], "comment_type": "block"}
log_message() {
    echo "[$(date)] $@" | tee -a "${LOGFILE:-/dev/stderr}"
}

# Source common functions
# Metadata: {"chunk_id": "phoenix_install_nvidia_driver-1.2", "keywords": ["common"], "comment_type": "block"}
if [[ -f "$(dirname "$0")/common.sh" ]]; then
    source "$(dirname "$0")/common.sh" || { log_message "Error: Failed to source common.sh"; exit 1; }
else
    log_message "Warning: common.sh not found, using fallback logging"
fi

# --- Source phoenix_config.sh for NVIDIA settings ---
# Meta {"chunk_id": "phoenix_install_nvidia_driver-1.2b", "keywords": ["config"], "comment_type": "block"}
PHOENIX_CONFIG_LOADED=0
for config_path in \
    "$(dirname "$0")/phoenix_config.sh" \
    "/usr/local/etc/phoenix_config.sh" \
    "./phoenix_config.sh"; do
    if [[ -f "$config_path" ]]; then
        # shellcheck source=/dev/null
        source "$config_path"
        if [[ "${PHOENIX_NVIDIA_DRIVER_VERSION:-}" ]]; then
            PHOENIX_CONFIG_LOADED=1
            log_message "Sourced configuration from $config_path."
            break
        else
            log_message "Sourced $config_path, but PHOENIX_NVIDIA_DRIVER_VERSION not found."
        fi
    fi
done

if [[ $PHOENIX_CONFIG_LOADED -ne 1 ]]; then
    log_message "Warning: phoenix_config.sh not found or PHOENIX_NVIDIA_DRIVER_VERSION not set. Using default/fallback values."
    # Fallback values for project requirements
    PHOENIX_NVIDIA_DRIVER_VERSION="${PHOENIX_NVIDIA_DRIVER_VERSION:-580.76.05}"
    # Note: Fixed the trailing space and brace in the URL
    PHOENIX_NVIDIA_RUNFILE_URL="${PHOENIX_NVIDIA_RUNFILE_URL:-https://us.download.nvidia.com/XFree86/Linux-x86_64/580.76.05/NVIDIA-Linux-x86_64-580.76.05.run}"
fi

# Log file (consistent with orchestrator)
LOGFILE="/var/log/proxmox_setup.log"

# Check if running as root
# Meta {"chunk_id": "phoenix_install_nvidia_driver-1.3", "keywords": ["root"], "comment_type": "block"}
if [[ $EUID -ne 0 ]]; then
    log_message "Error: This script must be run as root."
    exit 1
fi

# Parse command-line arguments
# Meta {"chunk_id": "phoenix_install_nvidia_driver-1.3", "keywords": ["args", "reboot"], "comment_type": "block"}
NO_REBOOT=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-reboot)
            NO_REBOOT=1
            shift
            ;;
        *)
            log_message "Error: Unknown option $1"
            exit 1
            ;;
    esac
done

# Check for NVIDIA GPU
# Metadata: {"chunk_id": "phoenix_install_nvidia_driver-1.6", "keywords": ["nvidia", "gpu"], "comment_type": "block"}
# Algorithm: GPU detection
# Checks for NVIDIA GPU via lspci
# Keywords: [nvidia, gpu]
if ! lspci | grep -i nvidia > /dev/null; then
    log_message "No NVIDIA GPU detected. Skipping driver installation."
    exit 0
fi

# --- Enhanced Function to Install NVIDIA Driver ---
# This function now includes robust checks and actions for kernel module handling.
install_nvidia_driver() {
    # --- Use version and URL from phoenix_config.sh or fallbacks ---
    local driver_version="$PHOENIX_NVIDIA_DRIVER_VERSION"
    local runfile="NVIDIA-Linux-x86_64-${driver_version}.run"
    local download_url="$PHOENIX_NVIDIA_RUNFILE_URL"
    local current_kernel_version
    current_kernel_version=$(uname -r)
    local pve_headers_package="pve-headers-${current_kernel_version}"

    log_message "Targeting NVIDIA driver version: $driver_version"
    log_message "Using download URL: $download_url"
    log_message "Current running kernel version: $current_kernel_version"

    # Check if NVIDIA driver is already installed with correct version
    if command -v nvidia-smi >/dev/null 2>&1; then
        installed_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null | head -n 1)
        if [[ "$installed_version" == "$driver_version" ]]; then
            log_message "NVIDIA driver version ${driver_version} already installed."

            # --- CRITICAL CHECK: Is the module loaded for the CURRENT kernel? ---
            if lsmod | grep -q nvidia; then
                log_message "NVIDIA kernel module is loaded for the current kernel ($current_kernel_version)."
                # Check DKMS status for current kernel
                local dkms_status_line
                dkms_status_line=$(dkms status | grep "^nvidia/${driver_version}," | grep "$current_kernel_version" || true)
                if echo "$dkms_status_line" | grep -q "installed"; then
                    log_message "NVIDIA DKMS module is installed for the current kernel ($current_kernel_version)."
                    log_message "Driver $driver_version is correctly installed and active for the current kernel."
                    return 0 # Success: Already correctly installed and running
                elif echo "$dkms_status_line" | grep -q "built"; then
                    log_message "Warning: NVIDIA DKMS module is built but not installed for the current kernel ($current_kernel_version). Attempting to install..."
                    if dkms install "nvidia/${driver_version}" -k "${current_kernel_version}"; then
                         log_message "Successfully installed NVIDIA DKMS module for the current kernel ($current_kernel_version)."
                         # Module should be available now, but might need a reload or reboot to be active.
                         # We'll proceed with the full installation to be safe and consistent.
                    else
                         log_message "Error: Failed to install NVIDIA DKMS module for the current kernel ($current_kernel_version). Proceeding with fresh installation."
                         # Fall through to full installation
                    fi
                else
                     log_message "Info: NVIDIA DKMS status unclear for current kernel ($current_kernel_version). Proceeding with fresh installation check."
                     # Fall through to full installation
                fi
            else
                log_message "Info: NVIDIA driver $driver_version found, but kernel module is not loaded. Proceeding with installation check/reinstall."
            fi
            # If we reach here, there's a mismatch or issue with the current state, so proceed with checks/install.
        else
             log_message "NVIDIA driver version ${installed_version} found, but ${driver_version} is required. Proceeding with installation."
        fi
    fi

    # --- Clean up any existing NVIDIA driver installations ---
    log_message "Cleaning up existing NVIDIA driver installations..."
    if command -v nvidia-uninstall >/dev/null 2>&1; then
        nvidia-uninstall --silent || { log_message "Warning: Failed to run nvidia-uninstall, continuing."; }
    fi
    # Use purge to remove config files as well
    apt-get purge -y '~nvidia' || { log_message "Warning: Failed to purge NVIDIA packages, continuing."; }
    # Clean up any leftover dkms modules
    if dkms status | grep -q "nvidia/${driver_version}"; then
        log_message "Removing old NVIDIA DKMS modules..."
        dkms remove "nvidia/${driver_version}" --all || { log_message "Warning: Failed to remove old NVIDIA DKMS modules, continuing."; }
    fi

    # --- Install Project-Required Prerequisites ---
    log_message "Installing project-required build dependencies, tools, and kernel headers..."
    retry_command "apt-get update" || { log_message "Error: Failed to update package lists"; return 1; }
    # Ensure all specified packages from project requirements are installed
    # Ensure pve-headers for the CURRENT kernel are installed FIRST
    retry_command "apt-get install -y ${pve_headers_package} build-essential dkms pkg-config" || { log_message "Error: Failed to install essential kernel headers/build tools"; return 1; }
    # Install the rest of the prerequisites
    retry_command "apt-get install -y g++ freeglut3-dev libx11-dev libxmu-dev libxi-dev libglu1-mesa-dev libfreeimage-dev libglfw3-dev wget htop btop nvtop glances git pciutils cmake curl libcurl4-openssl-dev make" || { log_message "Error: Failed to install project-required dependencies"; return 1; }

    # Blacklist nouveau
    # Meta {"chunk_id": "phoenix_install_nvidia_driver-1.4", "keywords": ["nouveau", "driver"], "comment_type": "block"}
    # Algorithm: Nouveau driver blacklisting
    # Adds nouveau blacklist and modeset options to modprobe configuration
    # Keywords: [nouveau, driver]
    log_message "Blacklisting nouveau driver..."
    cat << EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF
    # Note: update-initramfs is called later, which incorporates this.

    # Download and install NVIDIA driver
    log_message "Downloading NVIDIA driver ${driver_version}..."
    if ! wget --quiet "$download_url" -O "$runfile"; then
        log_message "Error: Failed to download NVIDIA driver runfile from $download_url."
        return 1
    fi

    log_message "Installing NVIDIA driver ${driver_version} with..."
    chmod +x "$runfile"
    # The installer should build for the current kernel if headers are correct.
    if ! ./"$runfile" --silent --no-x-check --accept-license; then
        log_message "Error: NVIDIA driver installation failed."
        rm -f "$runfile"
        return 1
    fi
    # Note: Do not remove the runfile yet, as DKMS might need source files for compilation on reboot or module rebuild.

    # --- Enhanced Post-Installation Steps for Kernel Module Robustness ---
    log_message "Performing enhanced post-installation steps for kernel module robustness..."

    # 1. Ensure kernel headers package is correctly installed for the current running kernel
    # (This was part of dependencies, but explicitly checking/ensuring it's correct for the running kernel is robust)
    if ! dpkg -l | grep -q "^ii.*${pve_headers_package}"; then
        log_message "Installing/updating PVE kernel headers package: ${pve_headers_package}..."
        if ! apt-get install -y "${pve_headers_package}"; then
             log_message "Error: Failed to install PVE kernel headers ${pve_headers_package}. DKMS build will likely fail."
             # Clean up runfile on failure
             rm -f "$runfile"
             return 1
        fi
    else
        log_message "PVE kernel headers package ${pve_headers_package} is already installed and correct."
    fi

    # 2. Force DKMS to build and install the NVIDIA module for the current kernel
    # This is the key step to fix the kernel version mismatch issue identified.
    log_message "Forcing DKMS to build/install NVIDIA module for the current kernel (${current_kernel_version})..."
    # Remove any potentially stale/built module for this kernel first
    dkms remove "nvidia/${driver_version}" -k "${current_kernel_version}" --all 2>/dev/null || true
    # Add the module source to DKMS (installer should have done this, but ensure)
    if ! dkms add "nvidia/${driver_version}"; then
         log_message "Warning: Failed to add NVIDIA module source to DKMS. It might already be added."
    fi
    # Build and install for the current kernel
    if ! dkms install "nvidia/${driver_version}" -k "${current_kernel_version}"; then
        log_message "Error: Failed to build/install NVIDIA module via DKMS for kernel ${current_kernel_version}."
        # Clean up runfile on failure
        rm -f "$runfile"
        return 1
    fi
    log_message "DKMS build/install for NVIDIA module completed successfully for kernel ${current_kernel_version}."

    # 3. Load the NVIDIA kernel module explicitly
    log_message "Loading NVIDIA kernel module..."
    # Unload first if somehow loaded incorrectly or partially
    rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true
    # Load the main module, which should pull in dependencies
    if ! modprobe nvidia; then
        log_message "Error: Failed to load NVIDIA kernel module."
        # Clean up runfile on failure
        rm -f "$runfile"
        return 1
    fi
    log_message "NVIDIA kernel module loaded successfully."
    # --- End Enhanced Post-Installation Steps ---

    # Update initramfs to include the blacklist and any necessary modules
    log_message "Updating initramfs to incorporate changes..."
    if ! update-initramfs -u; then
        log_message "Warning: Failed to update initramfs. Continuing, but consider running 'update-initramfs -u' manually after."
    fi

    # Clean up the runfile after successful post-install steps
    rm -f "$runfile"

    # Verify installation
    # Meta {"chunk_id": "phoenix_install_nvidia_driver-1.10", "keywords": ["nvidia", "verify"], "comment_type": "block"}
    # Algorithm: Driver verification
    # Checks NVIDIA kernel module and nvidia-smi functionality
    # Keywords: [nvidia, verify]
    # Note: This verification now happens after the explicit module loading
    if ! lsmod | grep -q nvidia; then
        log_message "Error: NVIDIA module not loaded after post-install steps."
        return 1
    fi

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        log_message "Error: nvidia-smi not found after installation and module loading."
        return 1
    fi

    local nvidia_smi_output
    nvidia_smi_output=$(nvidia-smi 2>&1) || { log_message "Error: nvidia-smi command failed."; return 1; }
    local installed_drv_version
    installed_drv_version=$(echo "$nvidia_smi_output" | grep "Driver Version" | awk '{print $3}')
    if [[ "$installed_drv_version" != "$driver_version" ]]; then
         log_message "Error: Driver version mismatch after installation. Expected $driver_version, got $installed_drv_version."
         return 1
    fi
    log_message "NVIDIA driver ${driver_version} installed and verified successfully."
    log_message "nvidia-smi output:"
    log_message "$nvidia_smi_output"
    return 0
}
# --- End Enhanced Function ---

# Function to install nvtop
# Metadata: {"chunk_id": "phoenix_install_nvidia_driver-1.9", "keywords": ["nvtop"], "comment_type": "block"}
install_nvtop() {
    log_message "Installing nvtop..."
    retry_command "apt-get install -y nvtop" || { log_message "Error: Failed to install nvtop, but continuing."; return 1; }
    if command -v nvtop >/dev/null 2>&1; then
        log_message "nvtop installed successfully."
    else
        log_message "Error: Failed to verify nvtop installation."
        return 1
    fi
    return 0
}

# Main execution
log_message "Starting NVIDIA driver (${PHOENIX_NVIDIA_DRIVER_VERSION}) and nvtop installation..."

# Install driver and tools
driver_installed=0
if install_nvidia_driver; then
    driver_installed=1
else
    log_message "Failed to install NVIDIA driver version ${PHOENIX_NVIDIA_DRIVER_VERSION}."
    exit 1
fi

install_nvtop

# Reboot if driver was installed
# Metadata: {"chunk_id": "phoenix_install_nvidia_driver-1.11", "keywords": ["initramfs", "reboot"], "comment_type": "block"}
if [[ "$driver_installed" -eq 1 ]]; then
    log_message "NVIDIA driver (${PHOENIX_NVIDIA_DRIVER_VERSION}) installation and post-install steps completed successfully."
    log_message "A reboot is STRONGLY RECOMMENDED to ensure stability, proper DKMS integration, and initramfs updates take full effect."
    if [[ "$NO_REBOOT" -eq 0 ]]; then
        log_message "Rebooting system in 15 seconds. Press Ctrl+C to cancel."
        sleep 15
        reboot
    else
        log_message "Reboot skipped due to --no-reboot flag. Please reboot manually as soon as possible to apply all changes and ensure stability."
    fi
fi

log_message "NVIDIA driver (${PHOENIX_NVIDIA_DRIVER_VERSION}) and tools installation completed successfully."
exit 0
