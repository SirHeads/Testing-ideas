#!/bin/bash

# File: hypervisor_feature_setup_vfio.sh
# Description: This script performs the initial, foundational setup for VFIO (Virtual Function I/O) GPU passthrough
#              on the Proxmox VE host. Its primary role is to ensure the correct kernel modules are loaded at boot
#              and to prevent default, conflicting graphics drivers from claiming the GPU hardware. This allows the
#              `vfio-pci` driver to take control of the GPU, making it available for direct passthrough to guest
#              environments (LXC containers or VMs). This script represents "Phase 1" of the GPU setup process.
#
# Dependencies:
#   - `update-initramfs`: To apply module changes to the initial RAM disk.
#
# Inputs:
#   - None. The script applies a static, universal configuration required for VFIO.
#
# Outputs:
#   - Creates or modifies `/etc/modprobe.d/blacklist-nouveau.conf` to disable the nouveau driver.
#   - Modifies `/etc/modprobe.d/pve-blacklist.conf` to disable the nvidiafb driver.
#   - Modifies `/etc/modules` to ensure VFIO modules are loaded on boot.
#   - Updates the system's initramfs.
#   - Logs a message indicating that a reboot is required.
#   - Exit Code: 0 on success.

# =====================================================================================
# Function: add_line_if_not_exists
# Description: An idempotent helper function that appends a given line to a file, but only
#              if the line does not already exist in the file. This prevents duplicate
#              entries when the script is run multiple times.
# Arguments:
#   $1 - The line of text to add.
#   $2 - The path to the file.
# Returns:
#   None.
# =====================================================================================
add_line_if_not_exists() {
    local line="$1"
    local file="$2"
    # Use grep -qF to perform a quiet (-q), fixed-string (-F) search.
    grep -qF -- "$line" "$file" || echo "$line" >> "$file"
}

# Blacklist the open-source `nouveau` driver.
# This is a critical step, as the nouveau driver will conflict with the proprietary NVIDIA
# driver and prevent vfio-pci from binding to the GPU.
cat > /etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

# Blacklist the `nvidiafb` driver, which is a legacy framebuffer driver that can also
# interfere with GPU passthrough.
add_line_if_not_exists "blacklist nvidiafb" "/etc/modprobe.d/pve-blacklist.conf"

# Ensure the necessary VFIO kernel modules are loaded at boot time by adding them to /etc/modules.
# - vfio: The core VFIO module.
# - vfio_pci: The module that handles PCI device passthrough.
# - vfio_iommu_type1: The IOMMU driver for the system.
# - vfio_virqfd: A module for virtual interrupt handling.
add_line_if_not_exists "vfio" "/etc/modules"
add_line_if_not_exists "vfio_pci" "/etc/modules"
add_line_if_not_exists "vfio_iommu_type1" "/etc/modules"
add_line_if_not_exists "vfio_virqfd" "/etc/modules"

# Update the initramfs. This is essential to ensure that the module and blacklist
# changes are applied early in the boot process.
update-initramfs -u -k all

echo "VFIO configuration complete. A reboot is required for changes to take effect."