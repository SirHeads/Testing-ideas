#!/bin/bash
#
# File: feature_install_docker.sh
# Description: This feature script automates the installation and configuration of Docker Engine,
#              NVIDIA Container Toolkit, and Portainer within a Proxmox LXC container.
#              It is designed to be called by the main orchestrator and is fully idempotent.
# Version: 1.0.0
# Author: Roo (AI Engineer)

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Source common utilities ---
source "$(dirname "$0")/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""

# =====================================================================================
# Function: parse_arguments
# Description: Parses the CTID from command-line arguments.
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Executing Docker feature for CTID: $CTID"
}

# =====================================================================================
# Function: install_and_configure_docker
# Description: Orchestrates the complete installation and configuration of Docker and its components.
# =====================================================================================
install_and_configure_docker() {
    ensure_nvidia_repo_is_configured "$CTID"
    log_info "Starting Docker installation and configuration in CTID: $CTID"

    # Idempotency Check
    if pct_exec "$CTID" command -v docker &>/dev/null && \
       pct_exec "$CTID" systemctl is-active docker &>/dev/null; then
        log_info "Docker already appears to be installed and running in CTID $CTID. Skipping installation."
    else
        # Add Docker Official Repository
        log_info "Adding Docker official repository in CTID: $CTID"
        pct_exec "$CTID" apt-get update
        pct_exec "$CTID" apt-get install -y ca-certificates curl gnupg lsb-release
        pct_exec "$CTID" mkdir -p /etc/apt/keyrings
        if [ ! -f "/etc/apt/keyrings/docker.gpg" ]; then
            pct_exec "$CTID" bash -c "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
            pct_exec "$CTID" chmod a+r /etc/apt/keyrings/docker.gpg
        else
            log_info "Docker GPG key already exists. Skipping download."
        fi
        pct_exec "$CTID" bash -c "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null"
        pct_exec "$CTID" apt-get update

        # Install Docker Engine
        log_info "Installing Docker Engine in CTID: $CTID"
        pct_exec "$CTID" apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi

    # --- Conditional NVIDIA Container Toolkit Installation ---
    local gpu_assignment=$(jq_get_value "$CTID" ".gpu_assignment" || echo "none")
    if [ "$gpu_assignment" != "none" ]; then
        log_info "GPU assignment found. Installing and configuring NVIDIA Container Toolkit..."
        ensure_nvidia_repo_is_configured "$CTID"

        if pct_exec "$CTID" dpkg -l | grep -q nvidia-container-toolkit; then
            log_info "NVIDIA Container Toolkit already installed in CTID $CTID."
        else
            log_info "Installing NVIDIA Container Toolkit in CTID: $CTID"
            pct_exec "$CTID" apt-get install -y nvidia-container-toolkit
        fi

        # --- Safely merge NVIDIA runtime configuration using jq ---
        log_info "Configuring Docker daemon for NVIDIA runtime in CTID: $CTID"
        local docker_daemon_config_file="/etc/docker/daemon.json"
        local nvidia_runtime_config='{ "default-runtime": "nvidia", "runtimes": { "nvidia": { "path": "/usr/bin/nvidia-container-runtime", "runtimeArgs": [] } } }'

        # Ensure the /etc/docker directory and daemon.json file exist
        pct_exec "$CTID" bash -c "mkdir -p /etc/docker && touch $docker_daemon_config_file"

        # Merge the new config with the existing one, handling empty file case
        pct_exec "$CTID" bash -c "jq -s 'if (.[0] | type) == \"null\" then {} else .[0] end * .[1]' '$docker_daemon_config_file' <(echo '$nvidia_runtime_config') > /tmp/daemon.json.tmp && mv /tmp/daemon.json.tmp '$docker_daemon_config_file'"
    else
        log_info "No GPU assignment found. Skipping NVIDIA Container Toolkit installation."
    fi

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
setup_portainer() {
    local portainer_role
    portainer_role=$(jq_get_value "$CTID" ".portainer_role" || echo "none")

    if [ "$portainer_role" == "none" ]; then
        log_info "Portainer role is 'none'. Skipping Portainer setup for CTID $CTID."
        return 0
    fi

    log_info "Setting up Portainer ($portainer_role) in CTID: $CTID"

    if [ "$portainer_role" == "server" ]; then
        if pct_exec "$CTID" docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
            log_info "Portainer server container already exists in CTID $CTID."
        else
            log_info "Deploying Portainer server container in CTID: $CTID"
            pct_exec "$CTID" docker volume create portainer_data
            pct_exec "$CTID" docker run -d -p 9443:9443 -p 9001:9001 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
        fi
    elif [ "$portainer_role" == "agent" ]; then
        if pct_exec "$CTID" docker ps -a --format '{{.Names}}' | grep -q "^portainer_agent$"; then
            log_info "Portainer agent container already exists in CTID $CTID."
        else
            log_info "Deploying Portainer agent container in CTID: $CTID"
            local portainer_server_ip
            portainer_server_ip=$(jq_get_value "$CTID" ".portainer_server_ip")
            local portainer_agent_port
            portainer_agent_port=$(jq_get_value "$CTID" ".portainer_agent_port")
            local agent_cluster_addr="tcp://${portainer_server_ip}:${portainer_agent_port}"

            pct_exec "$CTID" docker run -d -p 9001:9001 --name portainer_agent --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker/volumes:/var/lib/docker/volumes -e AGENT_CLUSTER_ADDR="$agent_cluster_addr" portainer/agent
        fi
    fi
}

# =====================================================================================
# Function: main
# Description: Main entry point for the Docker feature script.
# =====================================================================================
main() {
    parse_arguments "$@"
    install_and_configure_docker
    setup_portainer
    exit_script 0
}

main "$@"