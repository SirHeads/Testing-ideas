#!/bin/bash

# This script configures the Proxmox host for VFIO GPU passthrough.
# It ensures that the necessary kernel parameters, modules, and driver blacklists are in place.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Idempotency Checks ---

# Check if intel_iommu=on is already in /etc/default/grub
if grep -q "intel_iommu=on" /etc/default/grub; then
    echo "Kernel command line already configured for IOMMU."
else
    echo "Configuring kernel command line for IOMMU..."
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on /' /etc/default/grub
    update-grub
    echo "Kernel command line updated."
fi

# Check and add VFIO modules to /etc/modules
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
echo "Updating initramfs..."
update-initramfs -u

echo "VFIO configuration complete. A system reboot is required for changes to take effect."
