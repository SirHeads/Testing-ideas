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
    ensure_nvidia_repo_is_configured "$CTID" # Ensure NVIDIA repository is configured (for toolkit)
    log_info "Starting Docker installation and configuration in CTID: $CTID"

    # Idempotency Check
    # Idempotency Check: Check if Docker is already installed and running
    if pct_exec "$CTID" command -v docker &>/dev/null && \
       pct_exec "$CTID" systemctl is-active docker &>/dev/null; then
        log_info "Docker already appears to be installed and running in CTID $CTID. Skipping installation."
    else
        # Add Docker Official Repository
        log_info "Adding Docker official repository in CTID: $CTID"
        pct_exec "$CTID" apt-get update
        pct_exec "$CTID" apt-get install -y ca-certificates curl gnupg lsb-release
        pct_exec "$CTID" mkdir -p /etc/apt/keyrings
        pct_exec "$CTID" curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.gpg
        pct_exec "$CTID" gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg /tmp/docker.gpg
        pct_exec "$CTID" chmod a+r /etc/apt/keyrings/docker.gpg
        pct_exec "$CTID" rm /tmp/docker.gpg
        pct_exec "$CTID" bash -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null"
        pct_exec "$CTID" apt-get update

        # Install Docker Engine
        # Install Docker Engine components
        log_info "Installing Docker Engine in CTID: $CTID"
        pct_exec "$CTID" apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi

    # --- Conditional NVIDIA Container Toolkit Installation ---
    # Conditional NVIDIA Container Toolkit Installation based on GPU assignment
    local gpu_assignment=$(jq_get_value "$CTID" ".gpu_assignment" || echo "none") # Retrieve GPU assignment from config
    if [ "$gpu_assignment" != "none" ]; then
        log_info "GPU assignment found. Installing and configuring NVIDIA Container Toolkit..."
        ensure_nvidia_repo_is_configured "$CTID" # Ensure NVIDIA repository is configured

        # Check if NVIDIA Container Toolkit is already installed
        if pct_exec "$CTID" bash -c "dpkg -l | grep -q nvidia-container-toolkit"; then
            log_info "NVIDIA Container Toolkit already installed in CTID $CTID."
        else
            log_info "Installing NVIDIA Container Toolkit in CTID: $CTID"
            pct_exec "$CTID" apt-get install -y nvidia-container-toolkit
        fi

        # --- Safely merge NVIDIA runtime configuration using jq ---
        # Safely merge NVIDIA runtime configuration into Docker daemon.json using jq
        log_info "Configuring Docker daemon for NVIDIA runtime in CTID: $CTID"
        local docker_daemon_config_file="/etc/docker/daemon.json" # Path to Docker daemon configuration
        local nvidia_runtime_config='{ "default-runtime": "nvidia", "runtimes": { "nvidia": { "path": "/usr/bin/nvidia-container-runtime", "runtimeArgs": [] } } }' # NVIDIA runtime config snippet

        # Ensure the /etc/docker directory and daemon.json file exist
        # Ensure the /etc/docker directory and daemon.json file exist
        pct_exec "$CTID" bash -c "mkdir -p /etc/docker && touch $docker_daemon_config_file"

        # Merge the new config with the existing one, handling empty file case
        pct_exec "$CTID" bash -c "jq -s 'if (.[0] | type) == \"null\" then {} else .[0] end * .[1]' '$docker_daemon_config_file' <(echo '$nvidia_runtime_config') > /tmp/daemon.json.tmp && mv /tmp/daemon.json.tmp '$docker_daemon_config_file'"
    else
        log_info "No GPU assignment found. Skipping NVIDIA Container Toolkit installation."
    fi

    # Start and enable Docker service
    # Start and enable Docker service
    log_info "Starting and enabling Docker service in CTID: $CTID"
    pct_exec "$CTID" systemctl restart docker
    pct_exec "$CTID" systemctl enable docker

    log_info "Docker installation and configuration complete for CTID $CTID."
}

# =====================================================================================
# Function: setup_portainer
# Description: Deploys Portainer server or agent based on the container's configuration.
# =====================================================================================
# =====================================================================================
# Function: setup_portainer
# Description: Deploys Portainer (either server or agent) within the LXC container
#              based on the `portainer_role` defined in the container's configuration.
#              It performs idempotency checks to avoid re-deploying existing containers.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if Portainer deployment commands fail.
# =====================================================================================
setup_portainer() {
    local portainer_role # Variable to store Portainer role
    portainer_role=$(jq_get_value "$CTID" ".portainer_role" || echo "none") # Retrieve Portainer role from config

    # Skip Portainer setup if role is 'none'
    if [ "$portainer_role" == "none" ]; then
        log_info "Portainer role is 'none'. Skipping Portainer setup for CTID $CTID."
        return 0
    fi

    log_info "Setting up Portainer ($portainer_role) in CTID: $CTID"

    # Deploy Portainer server or agent based on the configured role
    if [ "$portainer_role" == "server" ]; then
        # Check if Portainer server container already exists
        if pct_exec "$CTID" bash -c "docker ps -a --format '{{.Names}}' | grep -q \"^portainer$\""; then
            log_info "Portainer server container already exists in CTID $CTID."
        else
            log_info "Deploying Portainer server container in CTID: $CTID"
            pct_exec "$CTID" docker run -d -p 9443:9443 -p 9001:9001 --name portainer --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data \
                -v /certs:/certs:ro \
                portainer/portainer-ce:latest --ssl --sslcert /certs/portainer.phoenix.local.crt --sslkey /certs/portainer.phoenix.local.key
        fi
    elif [ "$portainer_role" == "agent" ]; then
        # Check if Portainer agent container already exists
        if pct_exec "$CTID" bash -c "docker ps -a --format '{{.Names}}' | grep -q \"^portainer_agent$\""; then
            log_info "Portainer agent container already exists in CTID $CTID."
        else
            log_info "Deploying Portainer agent container in CTID: $CTID"
            local portainer_server_ip # IP of the Portainer server
            portainer_server_ip=$(jq_get_value "$CTID" ".portainer_server_ip") # Retrieve server IP from config
            local portainer_agent_port # Port for the Portainer agent
            portainer_agent_port=$(jq_get_value "$CTID" ".portainer_agent_port") # Retrieve agent port from config
            local agent_cluster_addr="tcp://${portainer_server_ip}:${portainer_agent_port}" # Construct agent cluster address

            pct_exec "$CTID" docker run -d -p 9001:9001 --name portainer_agent --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v /var/lib/docker/volumes:/var/lib/docker/volumes \
                -e AGENT_CLUSTER_ADDR="$agent_cluster_addr" \
                portainer/agent
        fi
    fi
}

# =====================================================================================
# Function: main
# Description: Main entry point for the Docker feature script.
# =====================================================================================
# =====================================================================================
# Function: main
# Description: Main entry point for the Docker feature script.
#              It parses arguments, installs and configures Docker, and sets up Portainer.
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   Exits with status 0 on successful completion.
# =====================================================================================
main() {
    parse_arguments "$@" # Parse command-line arguments
    install_and_configure_docker # Install and configure Docker
    setup_portainer # Set up Portainer
    exit_script 0 # Exit successfully
}

main "$@"