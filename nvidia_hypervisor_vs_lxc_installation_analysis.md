# NVIDIA Installation Analysis: Hypervisor vs. LXC

This document analyzes the procedural differences between the NVIDIA driver installation scripts for the Proxmox hypervisor and for LXC containers. The goal is to identify discrepancies and formulate a plan to align the LXC installation process with the more robust hypervisor method.

## Hypervisor Installation (`hypervisor_feature_install_nvidia.sh`)

The hypervisor installation process is designed to be a single, authoritative operation directly on the Debian-based Proxmox host.

**Key Characteristics:**

- **Installation Source:** Exclusively uses the official NVIDIA `.run` file specified in the configuration. This acts as a single source of truth for the driver version.
- **Idempotency:** Checks if the correct driver version is already installed and functional via `nvidia-smi`. If so, it exits cleanly.
- **Aggressive Cleanup:** Before installation, it performs a thorough purge of any existing NVIDIA packages, DKMS modules, and configuration files. This ensures a clean slate and prevents conflicts from previous failed attempts.
- **Dependencies:** Installs kernel headers (`pve-headers`), build tools, and DKMS, which are necessary for compiling the kernel module.
- **Method:**
    1.  Purges all `*nvidia*` packages.
    2.  Removes old DKMS modules.
    3.  Installs kernel headers and build tools.
    4.  Blacklists the open-source `nouveau` driver.
    5.  Executes the `.run` file to install the full driver stack, including the kernel module.
    6.  Requires a system reboot to load the new kernel module.

## LXC Container Installation (`phoenix_hypervisor_feature_install_nvidia.sh`)

The LXC installation is a two-part process involving configuration on the host and driver installation within the Ubuntu-based container.

**Key Characteristics:**

- **Installation Source:** Uses a hybrid approach:
    1.  The NVIDIA CUDA `apt` repository for the CUDA Toolkit and container utilities.
    2.  The official NVIDIA `.run` file for the user-space driver components.
- **Idempotency:** Uses a custom script function (`is_feature_present_on_container`) to check if the installation has been run before.
- **Host-Level Configuration:** Modifies the container's `.conf` file to enable GPU passthrough by mounting host device files (`/dev/nvidia*`) and setting cgroup permissions.
- **No Cleanup:** Lacks a cleanup phase, which can leave the container in a broken state if a previous installation fails.
- **Method:**
    1.  **On Host:** Adds device mounts and cgroup rules to the LXC config file.
    2.  **On Host:** Restarts the container to apply the new configuration.
    3.  **In Container:** Adds the NVIDIA CUDA `apt` repository. **(This is the point of failure noted in the logs).**
    4.  **In Container:** Installs `cuda-toolkit-12-2`, `nvidia-container-toolkit`, etc., using `apt`.
    5.  **In Container:** Executes the `.run` file with flags (`--no-kernel-module`) to install only the user-space components.

## Core Discrepancies & Analysis of Failure

1.  **Complexity and Conflicting Sources:** The LXC script's primary weakness is its use of two different sources (`apt` and `.run` file) for the driver components. The `cuda-toolkit-12-2` package from `apt` has its own user-space driver dependencies, which can conflict with the version installed by the `.run` file. This dual-source approach is fragile.
2.  **Lack of Cleanup:** The absence of a cleanup phase in the LXC script makes it less resilient. A failed run can leave behind broken packages and repositories, causing subsequent attempts to fail.
3.  **Point of Failure:** The script fails when trying to add the `apt` repository inside the container via `pct exec`. The fact that the command works when run manually moments later suggests a potential race condition. The container may appear "initialized" and have network connectivity, but `apt` or `dpkg` services might not be fully ready, causing the chained `wget && dpkg` command to fail.

## Conclusion

The hypervisor script's strategy is superior due to its simplicity, aggressive cleanup, and reliance on a single source of truth. The LXC script should be refactored to mirror this approach as closely as possible, while respecting the constraints of a containerized environment.