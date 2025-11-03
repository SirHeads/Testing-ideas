#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_portainer.sh
# Description: This modular feature script automates the deployment of Portainer within a Docker-enabled
#              LXC container. It reads the `portainer_role` from the container's configuration in
#              `phoenix_lxc_configs.json` and deploys either the Portainer Server or the Portainer Agent
#              as a Docker container. This allows for centralized management of Docker environments
#              across the hypervisor. The script is idempotent, checking for existing Portainer
#              containers before attempting deployment, and is a key component for observability and
#              management in the Phoenix Hypervisor ecosystem.
#
# Dependencies:
#   - The 'docker' feature must be installed and running in the target container.
#   - phoenix_hypervisor_common_utils.sh: For shared functions.
#   - `jq` for parsing configuration.
#
# Inputs:
#   - $1 (CTID): The unique Container ID for the target LXC container.
#   - `phoenix_lxc_configs.json`: Reads `.portainer_role`, `.portainer_server_ip`, and
#     `.portainer_agent_port` to determine the correct deployment action.
#
# Outputs:
#   - Deploys a 'portainer' or 'portainer_agent' Docker container inside the target LXC.
#   - Logs deployment details to stdout and the main log file.
#   - Returns exit code 0 on success, non-zero on failure.
#
# Version: 1.1.0
# Author: Phoenix Hypervisor Team

# --- Shell Settings ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Source common utilities ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""

# =====================================================================================
# Function: parse_arguments
# Description: Parses the CTID from command-line arguments.
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        log_error "This script requires the LXC Container ID to install the Portainer feature."
        exit_script 2
    fi
    CTID="$1"
    log_info "Executing Portainer modular feature for CTID: $CTID"
}

# =====================================================================================
# Function: setup_portainer
# Description: Deploys Portainer server or agent based on the container's configuration.
# =====================================================================================
setup_portainer() {
    # Read the 'portainer_role' from the JSON config. Default to 'none' if not specified.
    local portainer_role
    portainer_role=$(jq_get_value "$CTID" ".portainer_role" || echo "none")

    # If the role is 'none', no action is required.
    if [ "$portainer_role" == "none" ]; then
        log_info "Portainer role is 'none'. Skipping Portainer setup for CTID $CTID."
        return 0
    fi

    log_info "Setting up Portainer with role '$portainer_role' in CTID: $CTID"

    # --- Dependency Check ---
    # Portainer runs as a Docker container, so Docker is a hard prerequisite.
    if ! is_command_available "$CTID" "docker"; then
        log_fatal "Docker is not installed in CTID $CTID. The 'portainer' feature requires the 'docker' feature to be installed first."
    fi

    if [ "$portainer_role" == "server" ]; then
        # --- Portainer Server Deployment ---
        log_info "Deploying Portainer Server..."
        local container_name="portainer"

        # Idempotency: Check if the container is already running.
        if pct exec "$CTID" -- docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            log_info "Portainer server container is already running."
        else
            # Clean up any stopped container with the same name before deploying.
            if pct exec "$CTID" -- docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
                log_warn "Found a non-running Portainer server container. Removing it before deployment."
                pct_exec "$CTID" -- docker rm "${container_name}"
            fi

            log_info "Deploying Portainer server container..."
            # This command deploys the Portainer Community Edition with SSL enabled.
            # It mounts the Docker socket to manage the local Docker instance, creates a persistent volume for data,
            # and mounts SSL certificates from a predefined location within the container.
            pct_exec "$CTID" -- docker run -d \
                -p 9443:9443 \
                -p 9001:9001 \
                --name "${container_name}" \
                --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data \
                -v /certs:/certs:ro \
                portainer/portainer-ce:latest --ssl --sslcert /certs/portainer.internal.thinkheads.ai.crt --sslkey /certs/portainer.internal.thinkheads.ai.key

            # Verify that the container started successfully.
            verify_docker_container_running "$CTID" "${container_name}"
        fi

    elif [ "$portainer_role" == "agent" ]; then
        # --- Portainer Agent Deployment ---
        log_info "Deploying Portainer Agent..."
        local container_name="portainer_agent"

        # Idempotency: Check if the agent container is already running.
        if pct exec "$CTID" -- docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            log_info "Portainer agent container is already running."
        else
            # Clean up any stopped agent container.
            if pct exec "$CTID" -- docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
                log_warn "Found a non-running Portainer agent container. Removing it before deployment."
                pct_exec "$CTID" -- docker rm "${container_name}"
            fi

            log_info "Deploying Portainer agent container..."
            # The agent requires the IP and port of the Portainer server to connect to.
            local portainer_server_ip
            portainer_server_ip=$(jq_get_value "$CTID" ".portainer_server_ip")
            local portainer_agent_port
            portainer_agent_port=$(jq_get_value "$CTID" ".portainer_agent_port")
            local agent_cluster_addr="tcp://${portainer_server_ip}:${portainer_agent_port}"

            # This command deploys the agent, mounting the Docker socket and volumes to allow the server to manage this node.
            pct_exec "$CTID" -- docker run -d \
                -p 9001:9001 \
                --name "${container_name}" \
                --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v /var/lib/docker/volumes:/var/lib/docker/volumes \
                -e AGENT_CLUSTER_ADDR="$agent_cluster_addr" \
                portainer/agent

            # Verify that the agent started successfully.
            verify_docker_container_running "$CTID" "${container_name}"
        fi
    else
        log_warn "Invalid Portainer role specified: '$portainer_role'. Must be 'server', 'agent', or 'none'."
    fi
}

# =====================================================================================
# Function: main
# Description: Main entry point for the Portainer feature script.
# =====================================================================================
main() {
    parse_arguments "$@"
    setup_portainer
    log_info "Successfully completed Portainer feature for CTID $CTID."
    exit_script 0
}

main "$@"