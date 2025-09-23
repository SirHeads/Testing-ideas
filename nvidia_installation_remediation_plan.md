# NVIDIA Installation Remediation Plan

This document outlines the plan to refactor the LXC container NVIDIA installation script (`phoenix_hypervisor_feature_install_nvidia.sh`) to align with the more robust and reliable methodology of the hypervisor installation script.

## I. Refactor the LXC NVIDIA Installation Script

The primary goal is to simplify the LXC installation process by adopting the single-source `.run` file method from the hypervisor script. This eliminates the complexity and potential for conflict introduced by using the `apt` repository.

### New LXC Installation Workflow

The refactored script will follow these steps:

1.  **Idempotency Check:**
    -   Execute `nvidia-smi` inside the container.
    -   If the command succeeds and the driver version matches the one specified in the `.run` file name (or a config value), the script will exit successfully.

2.  **Aggressive Cleanup (New):**
    -   Execute a comprehensive cleanup inside the container to remove all traces of previous NVIDIA installations.
    -   This includes purging `*nvidia*` and `*cuda*` packages via `apt`, removing related files, and cleaning up any old repository configurations.

3.  **Install Dependencies (Modified):**
    -   Install essential dependencies like `build-essential`, `pkg-config`, and `wget` inside the container.
    -   The kernel headers are not needed in the container, as the kernel module is already loaded on the host.

4.  **Driver Installation (Simplified):**
    -   Push the NVIDIA `.run` file from the host to the container's `/tmp` directory.
    -   Execute the `.run` file inside the container with flags appropriate for a user-space-only installation (e.g., `--no-kernel-module`, `--no-x-check`, `--no-nouveau-check`, `--no-opengl-files`). This will install the user-space driver, CUDA toolkit, and `nvidia-smi`.
    -   Remove the `.run` file from the container after installation.

5.  **Verification:**
    -   Run `nvidia-smi` inside the container to confirm the installation was successful.
    -   Run `nvcc --version` to verify the CUDA toolkit installation.

## II. Proposed `install_drivers_in_container` Function Rewrite

The core of the change will be in the `install_drivers_in_container` function within `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_nvidia.sh`.

```bash
install_drivers_in_container() {
    log_info "Starting robust NVIDIA driver and CUDA toolkit installation."

    # --- Stage 1: Idempotency Check ---
    log_info "Stage 1: Verifying existing NVIDIA installation."
    local host_driver_version
    host_driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -n 1)

    if pct_exec "$CTID" -- nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | grep -q "$host_driver_version"; then
        log_info "NVIDIA driver version ${host_driver_version} is already installed and verified in container. Exiting."
        return 0
    fi
    log_info "NVIDIA driver not found or version mismatch. Proceeding with installation."

    # --- Stage 2: Aggressive Cleanup ---
    log_info "Stage 2: Performing aggressive cleanup of previous NVIDIA installations."
    pct_exec "$CTID" -- bash -c "apt-get purge -y '*nvidia*' '*cuda*' && apt-get autoremove -y"

    # --- Stage 3: System Preparation ---
    log_info "Stage 3: Installing essential dependencies."
    pct_exec "$CTID" -- apt-get update
    pct_exec "$CTID" -- apt-get install -y build-essential pkg-config wget

    # --- Stage 4: Driver Installation from .run file ---
    log_info "Stage 4: Installing user-space driver and CUDA toolkit from .run file."
    local nvidia_runfile_url
    nvidia_runfile_url=$(jq_get_value "$CTID" ".nvidia_runfile_url")
    if [ -z "$nvidia_runfile_url" ] || [ "$nvidia_runfile_url" == "null" ]; then
        log_error "NVIDIA runfile URL is not defined for CTID $CTID."
        return 1
    fi

    local runfile_name
    runfile_name=$(basename "$nvidia_runfile_url")
    local container_runfile_path="/tmp/${runfile_name}"

    log_info "Downloading NVIDIA .run file and pushing to container..."
    wget -qO "/tmp/${runfile_name}" "$nvidia_runfile_url"
    run_pct_push "$CTID" "/tmp/${runfile_name}" "$container_runfile_path"
    rm "/tmp/${runfile_name}"

    log_info "Executing ${runfile_name} in container..."
    local install_command="bash ${container_runfile_path} --silent --no-x-check --no-nouveau-check --no-opengl-files --no-kernel-module --accept-license"
    pct_exec "$CTID" -- chmod +x "$container_runfile_path"
    if ! pct_exec "$CTID" -- $install_command; then
        log_error "NVIDIA .run file installation failed."
        pct_exec "$CTID" -- rm -f "$container_runfile_path"
        return 1
    fi
    pct_exec "$CTID" -- rm -f "$container_runfile_path"

    # --- Stage 5: Final Verification ---
    log_info "Stage 5: Final verification of NVIDIA components."
    if ! pct_exec "$CTID" -- nvidia-smi; then
        log_error "Final nvidia-smi verification failed."
        return 1
    fi
    if ! pct_exec "$CTID" -- nvcc --version; then
        log_error "Final nvcc verification failed."
        return 1
    fi

    log_info "NVIDIA driver and CUDA toolkit installation completed successfully."
}
```

This revised approach simplifies the installation, enhances its reliability, and aligns it with the proven methodology used for the hypervisor.