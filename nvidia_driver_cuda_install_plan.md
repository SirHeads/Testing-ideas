# NVIDIA Driver and CUDA Installation Remediation Plan (Corrected)

## 1. Overview

This document outlines the corrected implementation plan for the NVIDIA driver and CUDA toolkit installation within an LXC container. The previous plan was flawed and did not align with the Phoenix Hypervisor architecture. This version is based on a thorough review of the hypervisor-level installation scripts and the intended GPU passthrough strategy.

The core principle is that the **host** is responsible for installing the full NVIDIA driver with the kernel module, while the **LXC container** requires a user-space-only installation that matches the host driver version.

## 2. Identified Deficiencies in the Current Script

1.  **Incorrect Flags:** The use of `--no-kernel-module` is correct for the container, but the absence of other essential flags and dependencies is causing the installation to fail.
2.  **Missing Dependencies:** The container script does not install `libnvidia-container1`, which is essential for the user-space driver to function correctly.
3.  **CUDA Repository:** The CUDA repository configuration is functional but can be made more robust.
4.  **Verification:** The verification process is not comprehensive enough to ensure both the driver and CUDA toolkit are fully functional.

## 3. Corrected Implementation Script

The following script block should replace the `install_drivers_in_container` function in `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_nvidia.sh`.

```bash
# =====================================================================================
# Function: install_drivers_in_container (Corrected)
# Description: Installs the NVIDIA user-space driver and CUDA Toolkit inside the LXC container,
#              ensuring version alignment with the host driver.
# =====================================================================================
install_drivers_in_container() {
    log_info "Starting NVIDIA driver and CUDA installation in CTID: $CTID"

    # --- Configuration Loading ---
    local nvidia_runfile_url
    nvidia_runfile_url=$(jq -r '.nvidia_runfile_url' "$LXC_CONFIG_FILE")
    local cuda_version
    cuda_version=$(jq -r '.nvidia_driver.cuda_version' "$HYPERVISOR_CONFIG_FILE" | tr '.' '-')
    local cache_dir="/usr/local/phoenix_hypervisor/cache"

    if [ -z "$nvidia_runfile_url" ]; then
        log_fatal "NVIDIA runfile URL is not defined in the configuration."
    fi

    # --- 1. Install Dependencies ---
    log_info "Installing prerequisites in container..."
    pct_exec "$CTID" -- apt-get update
    pct_exec "$CTID" -- apt-get install -y --no-install-recommends \
        build-essential \
        wget \
        curl \
        gnupg \
        libnvidia-container1

    # --- 2. Download and Install the NVIDIA User-Space Driver ---
    log_info "Checking for cached NVIDIA runfile..."
    local runfile_name
    runfile_name=$(basename "$nvidia_runfile_url")
    local host_runfile_path="${cache_dir}/${runfile_name}"

    if [ ! -f "$host_runfile_path" ]; then
        log_warn "NVIDIA runfile not found in cache. Downloading..."
        if ! wget -O "$host_runfile_path" "$nvidia_runfile_url"; then
            log_fatal "Failed to download NVIDIA runfile from $nvidia_runfile_url."
        fi
    fi

    local container_runfile_path="/tmp/$runfile_name"
    log_info "Pushing runfile to container at $container_runfile_path..."
    if ! run_pct_push "$CTID" "$host_runfile_path" "$container_runfile_path"; then
        log_fatal "Failed to push NVIDIA driver to container."
    fi

    log_info "Making runfile executable and starting installation..."
    pct_exec "$CTID" -- chmod +x "$container_runfile_path"

    # Execute the installer with the correct flags for a user-space-only installation
    local DRIVER_INSTALL_OPTIONS="--silent --accept-license --no-kernel-module --no-x-check --no-nouveau-check --no-nvidia-modprobe"
    log_info "Running installer with options: $DRIVER_INSTALL_OPTIONS"
    if ! pct_exec "$CTID" -- "$container_runfile_path" $DRIVER_INSTALL_OPTIONS; then
        log_fatal "NVIDIA driver installation from runfile failed."
    fi
    log_info "NVIDIA user-space driver installation script finished."

    # --- 3. Verify Driver Installation ---
    log_info "Verifying NVIDIA driver installation with nvidia-smi..."
    if ! pct_exec "$CTID" -- nvidia-smi; then
        log_fatal "NVIDIA driver verification failed. 'nvidia-smi' command failed or returned an error."
    fi
    log_success "NVIDIA driver verification successful. 'nvidia-smi' is responsive."

    # --- 4. Configure CUDA Network Repository ---
    log_info "Configuring NVIDIA CUDA repository..."
    ensure_nvidia_repo_is_configured "$CTID"

    # --- 5. Install CUDA Toolkit ---
    log_info "Installing CUDA Toolkit version ${cuda_version}..."
    if ! pct_exec "$CTID" -- apt-get install -y "cuda-toolkit-${cuda_version}"; then
        log_fatal "Failed to install CUDA Toolkit."
    fi

    # --- 6. Final Verification ---
    log_info "Verifying CUDA installation with nvcc..."
    if ! pct_exec "$CTID" -- /usr/local/cuda/bin/nvcc --version; then
        log_warn "CUDA 'nvcc' command not found or failed. The installation may be incomplete."
    else
        log_success "CUDA Toolkit verification successful."
    fi

    # --- Cleanup ---
    log_info "Cleaning up runfile from container..."
    pct_exec "$CTID" -- rm "$container_runfile_path"

    log_success "NVIDIA driver and CUDA installation process finished for CTID $CTID."
}
```

## 4. Next Steps

1.  **Review and Approve:** Please review this corrected plan for accuracy and completeness.
2.  **Switch to Code Mode:** Once approved, we will switch to **Code** mode to implement the changes.
3.  **Implementation:** The developer in **Code** mode will replace the existing `install_drivers_in_container` function in [`usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_nvidia.sh`](usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_nvidia.sh) with the corrected script block provided above.