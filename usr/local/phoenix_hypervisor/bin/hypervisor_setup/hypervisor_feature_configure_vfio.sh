#!/bin/bash

# File: hypervisor_feature_configure_vfio.sh
# Description: This script performs the declarative configuration of the Proxmox host for VFIO GPU passthrough.
#              Its primary role is to prepare the hypervisor to release control of physical NVIDIA GPUs,
#              making them available for direct assignment to guest environments like LXC containers or VMs.
#              This is a critical step in the orchestration process for enabling hardware acceleration for AI/ML workloads.
#              The script is designed to be idempotent, meaning it can be run multiple times without causing unintended side effects.
#
# Dependencies:
#   - /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh (for logging and utilities, assumed to be sourced by the orchestrator)
#   - `update-grub` command
#   - `update-initramfs` command
#
# Inputs:
#   - This script reads the state of the system's GRUB configuration (`/etc/default/grub`), loaded kernel modules (`/etc/modules`),
#     and modprobe configurations (`/etc/modprobe.d/`).
#   - GPU_IDS are currently hardcoded but are intended to be dynamically supplied in a production environment.
#
# Outputs:
#   - Modifies `/etc/default/grub` to enable the IOMMU.
#   - Appends required VFIO modules to `/etc/modules`.
#   - Creates `/etc/modprobe.d/vfio.conf` to bind specific GPU devices to the vfio-pci driver.
#   - Creates or modifies `/etc/modprobe.d/blacklist.conf` to prevent host drivers from claiming the GPUs.
#   - Updates the initial RAM filesystem (initramfs).
#   - Produces log output to stdout, indicating the steps being taken.
#   - Exit Code: 0 on success, non-zero on failure.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Idempotency Checks ---
# The following sections check the current system configuration to ensure that changes are only made
# if they are not already present. This makes the script safe to re-run as part of a declarative configuration workflow.

# Check if intel_iommu=on is already in /etc/default/grub
# The IOMMU (Input-Output Memory Management Unit) is a hardware feature that allows guest operating systems
# to have direct access to hardware devices. Enabling it is a prerequisite for VFIO passthrough.
if grep -q "intel_iommu=on" /etc/default/grub; then
    echo "Kernel command line already configured for IOMMU."
else
    echo "Configuring kernel command line for IOMMU..."
    # This command adds 'intel_iommu=on' to the default Linux kernel command line parameters in the GRUB configuration.
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on /' /etc/default/grub
    # After modifying the GRUB configuration, the bootloader must be updated.
    update-grub
    echo "Kernel command line updated."
fi

# Check and add VFIO modules to /etc/modules
# These kernel modules are essential for VFIO functionality. Loading them at boot ensures that the system is ready for device passthrough.
# - vfio: The core VFIO module.
# - vfio_iommu_type1: The IOMMU driver for the system.
# - vfio_pci: The module that handles PCI device passthrough.
# - vfio_virqfd: A module for virtual interrupt handling.
MODULES=("vfio" "vfio_iommu_type1" "vfio_pci" "vfio_virqfd")
for module in "${MODULES[@]}"; do
    if grep -q "^${module}$" /etc/modules; then
        echo "Module ${module} already configured in /etc/modules."
    else
        echo "Adding module ${module} to /etc/modules..."
        echo "${module}" >> /etc/modules
    fi
done

# Create /etc/modprobe.d/vfio.conf with GPU device IDs
# This configuration file tells the vfio-pci driver which PCI devices to claim.
# The device IDs are specific to the GPU hardware installed in the hypervisor.
# In a real scenario, these IDs should be dynamically fetched or passed as arguments.
# For this implementation, we'll use placeholder IDs.
GPU_IDS="10de:1e84 10de:10f8" # Example: NVIDIA GeForce GTX 1080 Ti
VFIO_CONF="/etc/modprobe.d/vfio.conf"
if [ -f "${VFIO_CONF}" ] && grep -q "options vfio-pci ids=${GPU_IDS}" "${VFIO_CONF}"; then
    echo "VFIO configuration already exists for GPU IDs."
else
    echo "Creating VFIO configuration for GPU IDs..."
    echo "options vfio-pci ids=${GPU_IDS}" > "${VFIO_CONF}"
fi

# Create /etc/modprobe.d/blacklist.conf to blacklist NVIDIA drivers
# To allow vfio-pci to claim the GPU, we must prevent the host's native NVIDIA drivers
# (and the open-source nouveau driver) from binding to the device at boot.
BLACKLIST_CONF="/etc/modprobe.d/blacklist.conf"
DRIVERS_TO_BLACKLIST=("nouveau" "nvidia" "nvidiafb" "nvidia-drm")
for driver in "${DRIVERS_TO_BLACKLIST[@]}"; do
    if [ -f "${BLACKLIST_CONF}" ] && grep -q "^blacklist ${driver}$" "${BLACKLIST_CONF}"; then
        echo "Driver ${driver} is already blacklisted."
    else
        echo "Blacklisting driver ${driver}..."
        echo "blacklist ${driver}" >> "${BLACKLIST_CONF}"
    fi
done

# Update initramfs
# After changing kernel modules and modprobe configurations, the initial RAM filesystem (initramfs)
# must be updated to ensure these changes are applied early in the boot process.
echo "Updating initramfs..."
update-initramfs -u

echo "VFIO configuration complete. A system reboot is required for changes to take effect."
