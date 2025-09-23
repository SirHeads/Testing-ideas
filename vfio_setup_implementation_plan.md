# VFIO Setup Implementation Plan

## 1. Objective

This plan details the steps required to create a new script for configuring VFIO on the Proxmox host and integrate it into the `phoenix_orchestrator.sh` script. This will resolve the GPU passthrough failure by ensuring the necessary kernel modules are loaded and conflicting drivers are blacklisted.

## 2. New Script: `hypervisor_feature_setup_vfio.sh`

A new script will be created at `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_vfio.sh`.

### 2.1. Script Content

```bash
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
```

### 2.2. Make Script Executable

The script must be made executable:
```bash
chmod +x usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_vfio.sh
```

## 3. Integration into `phoenix_orchestrator.sh`

The `phoenix_orchestrator.sh` script must be modified to call the new VFIO setup script.

### 3.1. Locate the `--setup-hypervisor` section

Find the case statement for the `--setup-hypervisor` option in `usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh`.

### 3.2. Add the call to the new script

Insert the following line at the beginning of the `--setup-hypervisor` block, before the NVIDIA driver installation:

```bash
bash "$PHOENIX_DIR/bin/hypervisor_setup/hypervisor_feature_setup_vfio.sh"
```

This ensures that the VFIO modules are configured and conflicting drivers are blacklisted before any attempt to install the NVIDIA drivers.