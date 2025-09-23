# NVIDIA Installation Remediation Plan

**Date:** 2025-09-22

**Author:** Roo

## 1. Executive Summary

This document outlines a comprehensive plan to address three critical issues in the LXC container feature installation process: a flawed order of operations in the NVIDIA driver installation, a race condition that leads to installation failures, and a logical flaw in feature inheritance detection. The proposed solutions will ensure a reliable, robust, and efficient container provisioning process.

## 2. Problem Analysis

### 2.1. NVIDIA Installation Order of Operations

The most critical issue is a flawed order of operations in the NVIDIA installation script. The script is attempting to install the CUDA toolkit *before* the NVIDIA driver has been fully installed and configured. This is a fundamental error that needs to be corrected to ensure a stable and functional NVIDIA environment.

### 2.2. NVIDIA Installation Race Condition

A race condition has been identified in the NVIDIA feature installation script. The script is checking for the NVIDIA device before it's actually available to the container, leading to a timeout and a fatal error. This is because the script is not waiting for the container to be fully initialized before proceeding with the device check.

### 2.3. Feature Inheritance

A logical flaw has been identified in the feature installation process for cloned LXC containers. Feature installation scripts are re-installing features that should have been inherited from their parent templates. The root cause of this issue is that the scripts are using state-based checks (e.g., checking for the existence of a package) instead of a configuration-based approach that correctly identifies inherited features.

## 3. Proposed Solution

### 3.1. NVIDIA Installation Order of Operations

The NVIDIA installation process will be re-structured to follow the correct order of operations:

1.  **Driver Installation:** The NVIDIA driver will be installed from the runfile.
2.  **Driver Verification:** The script will verify that the driver has been installed correctly by running `nvidia-smi`.
3.  **CUDA Repository Configuration:** The CUDA repository will be configured.
4.  **CUDA Toolkit Installation:** The CUDA toolkit will be installed from the repository.

### 3.2. NVIDIA Installation Race Condition

A new function, `wait_for_container_initialization`, will be introduced in the `phoenix_hypervisor_common_utils.sh` script. This function will ensure that the container's network is up and running before proceeding with any device checks. The `phoenix_hypervisor_feature_install_nvidia.sh` script will be modified to call this new function before attempting to check for the NVIDIA device.

### 3.3. Feature Inheritance

The state-based checks in all feature installation scripts will be replaced with a call to the `is_feature_present_on_container` function, which is already available in the `phoenix_hypervisor_common_utils.sh` script. This function recursively checks the container's configuration and its parent templates for the presence of a feature, ensuring that inherited features are correctly identified.

## 4. Implementation Plan

This is a planning document. The implementation of these changes will be handled by a separate development task. The following is a high-level overview of the implementation process:

1.  **Branching:** Create a new feature branch for this fix.
2.  **Development:**
    *   Implement the `wait_for_container_initialization` function in `phoenix_hypervisor_common_utils.sh`.
    *   Modify `phoenix_hypervisor_feature_install_nvidia.sh` to call the new function and to follow the correct order of operations.
    *   Modify all feature installation scripts to use `is_feature_present_on_container` for feature detection.
3.  **Testing:** Thoroughly test the changes to ensure that NVIDIA installation and feature inheritance are working correctly and that no regressions have been introduced.
4.  **Deployment:** Merge the changes into the main branch and deploy them to the production environment.

## 5. Conclusion

By implementing the solutions outlined in this document, we will address three critical issues in our feature installation process. This will result in a more reliable, robust, and efficient container provisioning system.