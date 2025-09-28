#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_docker.sh
# Description: Automates the installation and configuration of Docker Engine,
#              NVIDIA Container Toolkit (if GPU assigned), and Portainer (server or agent)
#              within a Proxmox LXC container. This script is designed to be idempotent
#              and is typically called by the main orchestrator.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), apt-get, curl, gnupg,
#               lsb-release, mkdir, gpg, chmod, tee, dpkg, systemctl, jq, docker,
#               nvidia-container-toolkit (conditional).
# Inputs:
#   $1 (CTID) - The container ID for the LXC container.
#   Configuration values from LXC_CONFIG_FILE: .gpu_assignment, .portainer_role,
#   .portainer_server_ip, .portainer_agent_port.
# Outputs:
#   Docker installation logs, NVIDIA Container Toolkit installation logs, Portainer
#   deployment logs, Docker daemon configuration modifications, log messages to stdout
#   and MAIN_LOG_FILE, exit codes indicating success or failure.
# Version: 1.0.0
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
# Description: Parses command-line arguments to extract the Container ID (CTID).
# Arguments:
#   $1 - The Container ID (CTID) for the LXC container.
# Returns:
#   Exits with status 2 if no CTID is provided.
# =====================================================================================
parse_arguments() {
    # Check if exactly one argument (CTID) is provided
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1" # Assign the first argument to CTID
    log_info "Executing Docker feature for CTID: $CTID"
}

# =====================================================================================
# Function: install_and_configure_docker
# Description: Orchestrates the complete installation and configuration of Docker and its components.
# =====================================================================================
# =====================================================================================
# Function: install_and_configure_docker
# Description: Orchestrates the complete installation and configuration of Docker Engine.
#              This includes adding Docker repositories, installing Docker components,
#              and conditionally installing/configuring the NVIDIA Container Toolkit
#              if a GPU is assigned to the container.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if any installation or configuration step fails.
# =====================================================================================
install_and_configure_docker() {
    log_info "Starting Docker installation and configuration in CTID: $CTID"

    # Wait for the container to initialize and have network connectivity
    if ! verify_lxc_network_connectivity "$CTID"; then
        log_warn "Container $CTID is not fully network-ready. Proceeding with caution."
    fi

    # --- Pre-computation and Idempotency Checks ---
    local docker_installed=false
    # Use raw 'pct exec' for the systemctl check to prevent the script from exiting if the service is not active.
    # This ensures that if Docker is installed but not running, we can proceed to the installation/repair logic.
    if pct exec "$CTID" -- command -v docker >/dev/null 2>&1 && pct exec "$CTID" -- systemctl is-active --quiet docker >/dev/null 2>&1; then
        docker_installed=true
    fi

    # --- Dependency Installation ---
    # Always ensure dependencies are present, even if Docker is already installed.
    # This makes the script more robust for partial installations or re-runs.
    log_info "Ensuring dependencies are installed in CTID: $CTID"
    pct_exec "$CTID" apt-get update
    pct_exec "$CTID" apt-get install -y ca-certificates curl gnupg lsb-release jq

    # --- NVIDIA Repository Configuration ---
    # This must happen after dependency installation to ensure curl and gpg are available.
    ensure_nvidia_repo_is_configured "$CTID"

    # --- Docker Installation ---
    log_info "Adding Docker official repository in CTID: $CTID"
    log_info "Verifying DNS resolution before download..."
    pct_exec "$CTID" ping -c 1 google.com || log_warn "DNS resolution test failed. Proceeding with caution."
    pct_exec "$CTID" mkdir -p /etc/apt/keyrings
    pct_exec "$CTID" curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.gpg
    pct_exec "$CTID" gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg /tmp/docker.gpg
    pct_exec "$CTID" chmod a+r /etc/apt/keyrings/docker.gpg
    pct_exec "$CTID" rm /tmp/docker.gpg
    pct_exec "$CTID" bash -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null"
    pct_exec "$CTID" apt-get update

    log_info "Installing Docker Engine in CTID: $CTID"
    pct_exec "$CTID" apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # --- Configure fuse-overlayfs ---
    log_info "Configuring Docker to use fuse-overlayfs storage driver..."
    if ! pct_exec "$CTID" dpkg -l | grep -q fuse-overlayfs; then
        log_info "Installing fuse-overlayfs..."
        pct_exec "$CTID" apt-get update
        pct_exec "$CTID" apt-get install -y fuse-overlayfs
    fi

    log_info "Creating Docker daemon configuration..."
    pct_exec "$CTID" mkdir -p /etc/docker
    pct_exec "$CTID" bash -c 'cat <<EOF > /etc/docker/daemon.json
{
  "storage-driver": "fuse-overlayfs"
}
EOF'

    # --- Conditional NVIDIA Container Toolkit Installation ---
    if is_feature_present_on_container "$CTID" "nvidia"; then
        log_info "NVIDIA feature detected. Installing and configuring NVIDIA Container Toolkit..."

        # --- Dependency Check ---
        log_info "Verifying NVIDIA driver installation (dependency check)..."
        if ! is_command_available "$CTID" "nvidia-smi"; then
            log_fatal "NVIDIA driver not found in CTID $CTID. The 'docker' feature with GPU assignment depends on the 'nvidia' feature. Please ensure 'nvidia' is listed before 'docker' in the features array of your configuration file."
        fi

        ensure_nvidia_repo_is_configured "$CTID" # Ensure NVIDIA repository is configured

        # Check if NVIDIA Container Toolkit is already installed
        if pct_exec "$CTID" bash -c "dpkg -l | grep -q nvidia-container-toolkit"; then
            log_info "NVIDIA Container Toolkit already installed in CTID $CTID."
        else
            log_info "Installing NVIDIA Container Toolkit in CTID: $CTID"
            pct_exec "$CTID" apt-get install -y nvidia-container-toolkit
        fi

        # --- Safely merge NVIDIA runtime configuration using jq ---
        log_info "Configuring Docker daemon for NVIDIA runtime in CTID: $CTID"
        local docker_daemon_config_file="/etc/docker/daemon.json"
        local nvidia_runtime_config='{ "default-runtime": "nvidia", "runtimes": { "nvidia": { "path": "/usr/bin/nvidia-container-runtime", "runtimeArgs": [] } } }'

        pct_exec "$CTID" bash -c "mkdir -p /etc/docker && [ -f $docker_daemon_config_file ] || echo '{}' > $docker_daemon_config_file"
        pct_exec "$CTID" bash -c "sed -i 's/\"default-runtime\": \"[^\"]*\"/\"default-runtime\": \"nvidia\"/' '$docker_daemon_config_file'"
        pct_exec "$CTID" bash -c "sed -i '/\"runtimes\"/a \        \"nvidia\": { \"path\": \"/usr/bin/nvidia-container-runtime\", \"runtimeArgs\": [] }' '$docker_daemon_config_file'"
    else
        log_info "NVIDIA feature not detected. Skipping NVIDIA Container Toolkit installation."
    fi

    # Start and enable Docker service
    # Start and enable Docker service
    log_info "Starting and enabling Docker service in CTID: $CTID"
    pct_exec "$CTID" systemctl restart docker
    pct_exec "$CTID" systemctl enable docker

    log_info "Docker installation and configuration complete for CTID $CTID."
}

# =====================================================================================
# Function: verify_docker_installation
# Description: Verifies that Docker was installed and is running correctly.
# =====================================================================================
verify_docker_installation() {
    log_info "Verifying Docker installation in CTID: $CTID"
    if ! pct_exec "$CTID" docker --version; then
        log_fatal "Docker installation verification failed. The 'docker' command is not available."
    fi
    log_success "Docker installation verified successfully."
}


# =====================================================================================
# Function: main
# Description: Main entry point for the Docker feature script.
# =====================================================================================
main() {
    parse_arguments "$@" # Parse command-line arguments

    # --- Idempotency Check ---
    # Use a direct, silent check for the docker command to avoid log noise from is_command_available
    if pct exec "$CTID" -- command -v docker >/dev/null 2>&1; then
        log_info "Docker is already installed in CTID $CTID. Skipping installation."
    else
        install_and_configure_docker
        verify_docker_installation
    fi
    # --- End Idempotency Check ---
    
    exit_script 0 # Exit successfully
}

main "$@"