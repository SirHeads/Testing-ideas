#!/bin/bash

# Idempotently configure VFIO for GPU passthrough

# Function to add a line to a file if it doesn't already exist
add_line_if_not_exists() {
    local line="$1"
    local file="$2"
    grep -qF -- "$line" "$file" || echo "$line" >> "$file"
}

# Blacklist nouveau driver
cat > /etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

# Blacklist nvidiafb driver
add_line_if_not_exists "blacklist nvidiafb" "/etc/modprobe.d/pve-blacklist.conf"

# Load VFIO modules at boot
add_line_if_not_exists "vfio" "/etc/modules"
add_line_if_not_exists "vfio_pci" "/etc/modules"
add_line_if_not_exists "vfio_iommu_type1" "/etc/modules"
add_line_if_not_exists "vfio_virqfd" "/etc/modules"

# Update initramfs
update-initramfs -u -k all

echo "VFIO configuration complete. A reboot is required for changes to take effect."