# LXC NVIDIA Prerequisite Installation Plan

## I. Objective

To enhance the reliability of the NVIDIA driver installation within LXC containers by installing the same prerequisite packages used on the hypervisor, excluding those that are host-specific.

## II. Analysis

The hypervisor installation script (`hypervisor_feature_install_nvidia.sh`) installs the following packages:
- `pve-headers` (Host-specific)
- `build-essential` (Container-safe)
- `dkms` (Host-specific)
- `pkg-config` (Container-safe)
- `wget` (Container-safe)

The current LXC script (`phoenix_hypervisor_feature_install_nvidia.sh`) does not explicitly install `build-essential` or `pkg-config`. This could lead to failures if the NVIDIA `.run` file needs to compile any user-space components.

## III. Implementation Strategy

The `install_drivers_in_container` function in `phoenix_hypervisor_feature_install_nvidia.sh` will be modified. A new step will be added to install the necessary prerequisites after the `apt update` command and before the main `cuda-toolkit` installation.

### Proposed Code Modification

The package installation line will be updated as follows:

**From:**
```bash
local packages_to_install="cuda-toolkit nvidia-container-toolkit"
```

**To:**
```bash
local packages_to_install="build-essential pkg-config wget cuda-toolkit nvidia-container-toolkit"
```

This change ensures that the container environment has the necessary build tools before attempting the more complex installation steps, mirroring the robust setup of the hypervisor.