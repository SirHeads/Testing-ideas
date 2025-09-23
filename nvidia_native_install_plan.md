# NVIDIA Driver and CUDA Toolkit Native Installation Plan

## 1. Executive Summary

The previous installation method using the NVIDIA `.run` file has proven to be unreliable, leading to communication failures between the user-space drivers and the host's kernel driver. This plan outlines a revised, definitive implementation strategy that abandons the `.run` file installer in favor of a native Ubuntu `apt` repository approach. This method is more robust, less prone to environment-specific issues, and aligns with Linux distribution best practices.

## 2. Problem Analysis

The user-provided logs clearly indicate that while the `.run` file executes, the resulting installation is faulty. The key failure point is `nvidia-smi`'s inability to communicate with the kernel driver. The logs also reveal that the container's `apt` repository is aware of the necessary `nvidia-utils` and driver packages, making a native installation feasible and highly desirable.

## 3. Revised Implementation Plan

The following shell script should replace the existing content of the `install_drivers_in_container` function within the NVIDIA feature script. It provides a complete, commented, and copy-pasteable solution for installing the NVIDIA driver and CUDA toolkit using `apt`.

### `install_drivers_in_container` Function

```bash
install_drivers_in_container() {
    log_info "Starting NVIDIA driver and CUDA toolkit installation using native apt packages."

    # --- 1. Add Graphics Drivers PPA ---
    # Add the official PPA to ensure access to the latest stable NVIDIA drivers.
    # The '-y' flag automatically confirms the addition of the PPA.
    log_info "Adding the graphics-drivers PPA..."
    add-apt-repository ppa:graphics-drivers/ppa -y
    if [ $? -ne 0 ]; then
        log_error "Failed to add the graphics-drivers PPA. Aborting."
        return 1
    fi

    # --- 2. Update Package Lists ---
    # Refresh the package lists to include the newly added PPA.
    log_info "Updating package lists..."
    apt-get update
    if [ $? -ne 0 ]; then
        log_error "Failed to update package lists. Aborting."
        return 1
    fi

    # --- 3. Install NVIDIA Driver ---
    # Install the server-grade driver metapackage. This package automatically
    # handles dependencies, including the correct nvidia-utils and nvidia-smi.
    log_info "Installing NVIDIA driver (nvidia-driver-535-server)..."
    apt-get install -y nvidia-driver-535-server
    if [ $? -ne 0 ]; then
        log_error "Failed to install nvidia-driver-535-server. Aborting."
        return 1
    fi

    # --- 4. Install CUDA Toolkit ---
    # Install the CUDA toolkit. It will resolve its dependencies against the
    # newly installed driver, ensuring compatibility.
    log_info "Installing CUDA toolkit..."
    apt-get install -y cuda-toolkit
    if [ $? -ne 0 ]; then
        log_error "Failed to install cuda-toolkit. Aborting."
        return 1
    fi

    # --- 5. Verification ---
    # Run nvidia-smi to confirm that the driver is installed and communicating
    # correctly with the kernel module.
    log_info "Verifying NVIDIA driver installation with nvidia-smi..."
    nvidia-smi
    if [ $? -ne 0 ]; then
        log_error "nvidia-smi verification failed. The driver may not be loaded correctly."
        return 1
    fi

    log_info "NVIDIA driver and CUDA toolkit installation completed successfully."
}
```

## 4. Next Steps

This plan will be passed to the Code mode for implementation. The Code mode will be responsible for replacing the existing `install_drivers_in_container` function with the one provided above.