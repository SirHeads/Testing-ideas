#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_docker.sh
# Description: This script is a modular feature installer responsible for creating a complete and secure
#              containerization environment within a target LXC container using Docker. As part of the
#              Phoenix Hypervisor's declarative setup, this script is invoked by the main orchestrator
#              when "docker" is specified in a container's `features` array in `phoenix_lxc_configs.json`.
#              It handles the installation of Docker Engine, configures the secure `fuse-overlayfs`
#              storage driver, and, if a GPU is assigned to the container, installs and configures the
#              NVIDIA Container Toolkit to enable GPU-accelerated Docker workloads. The script is
#              idempotent, ensuring that repeated executions do not alter the final configured state.
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: Provides shared functions for logging and container interaction.
#   - An active internet connection within the container for downloading packages.
#   - The 'nvidia' feature script must be run before this one if GPU support is required.
#
# Inputs:
#   - $1 (CTID): The unique Container ID for the target LXC container.
#   - Container configuration from `phoenix_lxc_configs.json`, specifically the `features` array
#     to determine if the NVIDIA toolkit is needed.
#
# Outputs:
#   - A fully installed and operational Docker environment inside the specified LXC container.
#   - Configuration of Docker's daemon.json with the `fuse-overlayfs` storage driver and
#     NVIDIA as the default runtime (if applicable).
#   - Detailed logs of the installation process to stdout and the main log file.
#   - Returns exit code 0 on success, non-zero on failure.
#
# Version: 1.1.0
# Author: Phoenix Hypervisor Team

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Source common utilities ---
# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""

# =====================================================================================
# Function: parse_arguments
# Description: Parses the CTID from command-line arguments.
# =====================================================================================
# =====================================================================================
# Function: parse_arguments
# Description: Validates and parses the command-line arguments provided to the script.
#              It requires a single argument: the CTID of the target LXC container.
#              This ensures that all subsequent operations are performed on the correct container.
# Arguments:
#   $1 - The Container ID (CTID) for the LXC container.
# Globals:
#   - CTID: This global variable is set with the value of $1 for use throughout the script.
# Returns:
#   - None. The script will exit with status 2 if the CTID is not provided.
# =====================================================================================
parse_arguments() {
    # The script cannot proceed without a target container. This check enforces that requirement.
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        log_error "This script requires the LXC Container ID to install the Docker feature."
        exit_script 2
    fi
    # Set the global CTID variable to the validated command-line argument.
    CTID="$1"
    log_info "Executing Docker modular feature for CTID: $CTID"
}

# =====================================================================================
# Function: install_and_configure_docker
# Description: Orchestrates the complete installation and configuration of Docker and its components.
# =====================================================================================
# =====================================================================================
# Function: install_and_configure_docker
# Description: This is the main workflow function that orchestrates the entire Docker setup process.
#              It follows a structured, idempotent process to ensure a consistent outcome. The key stages are:
#              1. Dependency Installation: Installs necessary tools like curl, gpg, and jq.
#              2. Docker Repository Setup: Adds the official Docker APT repository to the container's sources.
#              3. Docker Engine Installation: Installs docker-ce, cli, containerd, and the compose plugin.
#              4. Secure Storage Driver Configuration: Installs and configures `fuse-overlayfs`, which is the
#                 recommended storage driver for running Docker in unprivileged LXC containers for security.
#              5. Conditional NVIDIA Toolkit Installation: If the container is configured with the "nvidia"
#                 feature, it installs the NVIDIA Container Toolkit and sets NVIDIA as the default runtime,
#                 enabling GPU passthrough to Docker containers.
#              6. Service Management: Restarts and enables the Docker service to apply all configurations.
# Arguments:
#   None. It relies on the global CTID variable.
# Returns:
#   - None. The script will exit on failure due to `set -e`.
# =====================================================================================
install_and_configure_docker() {
    log_info "Starting Docker installation and configuration in CTID: $CTID"

    # A brief wait and network check can prevent failures in newly created containers that are not yet fully initialized.
    if ! verify_lxc_network_connectivity "$CTID"; then
        log_warn "Container $CTID is not fully network-ready. Proceeding with caution."
    fi

    # --- Dependency Installation ---
    # Ensure all necessary tools for the installation process are present.
    log_info "Ensuring dependencies (ca-certificates, curl, gnupg, lsb-release, jq) are installed in CTID: $CTID"
    pct_exec "$CTID" apt-get update
    pct_exec "$CTID" apt-get install -y ca-certificates curl gnupg lsb-release jq

    # --- Docker Installation ---
    # This block follows the official Docker installation guide to add the repository and install the packages.
    log_info "Adding Docker official GPG key and repository in CTID: $CTID"
    pct_exec "$CTID" mkdir -p /etc/apt/keyrings
    # Download the GPG key, de-armor it, and store it in the keyrings directory.
    pct_exec "$CTID" curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.gpg
    pct_exec "$CTID" gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg /tmp/docker.gpg
    pct_exec "$CTID" chmod a+r /etc/apt/keyrings/docker.gpg
    pct_exec "$CTID" rm /tmp/docker.gpg
    # Add the official Docker repository to the APT sources list.
    pct_exec "$CTID" bash -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null"
    pct_exec "$CTID" apt-get update

    log_info "Installing Docker Engine, CLI, Containerd, and Compose Plugin in CTID: $CTID"
    pct_exec "$CTID" apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # --- Configure fuse-overlayfs for Security ---
    # Using fuse-overlayfs is a critical security measure for running Docker inside an unprivileged LXC container.
    # It avoids the need for privileged operations that the default overlay2 driver would require.
    log_info "Configuring Docker to use fuse-overlayfs storage driver for enhanced security in unprivileged LXC."
    if ! pct_exec "$CTID" dpkg -l | grep -q fuse-overlayfs; then
        log_info "Installing fuse-overlayfs package..."
        pct_exec "$CTID" apt-get install -y fuse-overlayfs
    fi

    # Create the Docker daemon configuration file to specify the storage driver.
    log_info "Creating Docker daemon configuration at /etc/docker/daemon.json..."
    pct_exec "$CTID" mkdir -p /etc/docker
    pct_exec "$CTID" bash -c 'cat <<EOF > /etc/docker/daemon.json
{
  "storage-driver": "fuse-overlayfs"
}
EOF'

    # --- Conditional NVIDIA Container Toolkit Installation ---
    # This section makes the script adaptable to both CPU-only and GPU-enabled containers.
    if is_feature_present_on_container "$CTID" "nvidia"; then
        log_info "NVIDIA feature detected. Installing and configuring NVIDIA Container Toolkit for GPU support..."

        # The 'nvidia' feature, which installs the driver, is a hard dependency for GPU-enabled Docker.
        log_info "Verifying NVIDIA driver installation (dependency check)..."
        if ! is_command_available "$CTID" "nvidia-smi"; then
            log_fatal "NVIDIA driver not found in CTID $CTID. The 'docker' feature with GPU assignment depends on the 'nvidia' feature. Please ensure 'nvidia' is listed before 'docker' in the features array of your configuration file."
        fi

        # The NVIDIA repo is required for installing the container toolkit.
        ensure_nvidia_repo_is_configured "$CTID"

        # Install the toolkit if it's not already present.
        if pct_exec "$CTID" bash -c "dpkg -l | grep -q nvidia-container-toolkit"; then
            log_info "NVIDIA Container Toolkit already installed in CTID $CTID."
        else
            log_info "Installing NVIDIA Container Toolkit..."
            pct_exec "$CTID" apt-get install -y nvidia-container-toolkit
        fi

        # --- Safely merge NVIDIA runtime configuration using jq ---
        # This modifies the daemon.json file to make the NVIDIA runtime available and set it as the default.
        log_info "Configuring Docker daemon for NVIDIA runtime in CTID: $CTID"
        local docker_daemon_config_file="/etc/docker/daemon.json"
        # This JSON snippet contains the necessary configuration for the NVIDIA runtime.
        local nvidia_runtime_config='{ "default-runtime": "nvidia", "runtimes": { "nvidia": { "path": "/usr/bin/nvidia-container-runtime", "runtimeArgs": [] } } }'

        # Use jq to safely merge the existing configuration with the new NVIDIA runtime settings.
        # This is more robust than using sed, as it correctly handles JSON syntax.
        pct_exec "$CTID" bash -c "jq --argjson nvidia_config '${nvidia_runtime_config}' '. * \$nvidia_config' '${docker_daemon_config_file}' > /tmp/daemon.json.tmp && mv /tmp/daemon.json.tmp '${docker_daemon_config_file}'"
    else
        log_info "NVIDIA feature not detected. Skipping NVIDIA Container Toolkit installation."
    fi

    # Restarting the service applies all the configuration changes made to daemon.json.
    # Enabling the service ensures Docker starts automatically on container boot.
    log_info "Restarting and enabling Docker service in CTID: $CTID"
    pct_exec "$CTID" systemctl restart docker
    pct_exec "$CTID" systemctl enable docker

    log_info "Docker installation and configuration complete for CTID $CTID."
}

# =====================================================================================
# Function: verify_docker_installation
# Description: Performs a simple post-installation check to confirm that the Docker binary
#              is executable and the Docker service is responsive. This acts as a final
#              sanity check to catch any critical installation failures.
# Arguments:
#   None. Relies on the global CTID.
# Returns:
#   - Logs a success message or exits with a fatal error if verification fails.
# =====================================================================================
verify_docker_installation() {
    log_info "Verifying Docker installation in CTID: $CTID"
    # Running `docker --version` is a reliable way to confirm that the Docker client
    # can communicate with the Docker daemon.
    if ! pct_exec "$CTID" docker --version; then
        log_fatal "Docker installation verification failed. The 'docker' command is not available or the daemon is not responding."
    fi
    log_success "Docker installation verified successfully. Docker is active and ready."
}


# =====================================================================================
# Function: main
# Description: The main entry point for the script. It orchestrates the high-level
#              workflow: argument parsing, an idempotency check, installation,
#              verification, and final exit.
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   - Exits with status 0 on successful completion.
# =====================================================================================
main() {
    parse_arguments "$@"

    # --- Idempotency Check ---
    # This check prevents the script from re-running the entire installation process if Docker
    # is already installed. This makes the orchestrator's `apply_features` state more robust.
    if pct exec "$CTID" -- command -v docker >/dev/null 2>&1; then
        log_info "Docker command is already available in CTID $CTID. Skipping installation process."
        # Even if installed, ensure the service is running.
        log_info "Ensuring Docker service is active..."
        pct_exec "$CTID" systemctl restart docker
        pct_exec "$CTID" systemctl enable docker
    else
        # If Docker is not installed, run the full installation and verification workflow.
        install_and_configure_docker
        verify_docker_installation
    fi
    
    log_info "Successfully completed Docker feature for CTID $CTID."
    exit_script 0
}

# Execute the main function, passing all script arguments to it.
main "$@"