#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_portainer.sh
# Description: Deploys Portainer server or agent based on the container's configuration.
#              This script is designed to be idempotent and is typically called by the main orchestrator.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq, docker.
# Inputs:
#   $1 (CTID) - The container ID for the LXC container.
#   Configuration values from LXC_CONFIG_FILE: .portainer_role, .portainer_server_ip, .portainer_agent_port.
# Outputs:
#   Portainer deployment logs, log messages to stdout and MAIN_LOG_FILE, exit codes indicating success or failure.
# Version: 1.0.0
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
        exit_script 2
    fi
    CTID="$1"
    log_info "Executing Portainer feature for CTID: $CTID"
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
        # --- Refactored Portainer Server Deployment ---
        log_info "Checking status of Portainer server container in CTID $CTID..."

        # Check if the container is already running
        if pct exec "$CTID" -- docker ps --format '{{.Names}}' | grep -q "^portainer$"; then
            log_info "Portainer server container is already running in CTID $CTID."
        else
            # If not running, check if a stopped container exists and remove it
            if pct exec "$CTID" -- docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
                log_warn "Found a non-running Portainer server container. Removing it before deployment."
                pct_exec "$CTID" -- docker rm portainer
            fi

            # Deploy the container
            log_info "Deploying Portainer server container in CTID: $CTID"
            pct_exec "$CTID" -- docker run -d -p 9443:9443 -p 9001:9001 --name portainer --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data \
                -v /certs:/certs:ro \
                portainer/portainer-ce:latest --ssl --sslcert /certs/portainer.phoenix.local.crt --sslkey /certs/portainer.phoenix.local.key

            # Verify the container started successfully
            log_info "Verifying Portainer server startup..."
            local timeout=30
            local end_time=$((SECONDS + timeout))
            local started=false
            while [ $SECONDS -lt $end_time ]; do
                if pct exec "$CTID" -- docker ps --format '{{.Names}}' | grep -q "^portainer$"; then
                    log_success "Portainer server container started successfully."
                    started=true
                    break
                fi
                sleep 2
            done

            if [ "$started" = false ]; then
                log_error "Portainer server container failed to start within $timeout seconds."
                log_info "Dumping Portainer container logs for debugging:"
                pct_exec "$CTID" -- docker logs portainer
                log_fatal "Aborting due to Portainer startup failure."
            fi
        fi
    elif [ "$portainer_role" == "agent" ]; then
        # --- Refactored Portainer Agent Deployment ---
        log_info "Checking status of Portainer agent container in CTID $CTID..."

        # Check if the container is already running
        if pct exec "$CTID" -- docker ps --format '{{.Names}}' | grep -q "^portainer_agent$"; then
            log_info "Portainer agent container is already running in CTID $CTID."
        else
            # If not running, check if a stopped container exists and remove it
            if pct exec "$CTID" -- docker ps -a --format '{{.Names}}' | grep -q "^portainer_agent$"; then
                log_warn "Found a non-running Portainer agent container. Removing it before deployment."
                pct_exec "$CTID" -- docker rm portainer_agent
            fi

            # Deploy the container
            log_info "Deploying Portainer agent container in CTID: $CTID"
            local portainer_server_ip
            portainer_server_ip=$(jq_get_value "$CTID" ".portainer_server_ip")
            local portainer_agent_port
            portainer_agent_port=$(jq_get_value "$CTID" ".portainer_agent_port")
            local agent_cluster_addr="tcp://${portainer_server_ip}:${portainer_agent_port}"

            pct_exec "$CTID" -- docker run -d -p 9001:9001 --name portainer_agent --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v /var/lib/docker/volumes:/var/lib/docker/volumes \
                -e AGENT_CLUSTER_ADDR="$agent_cluster_addr" \
                portainer/agent
        fi
    fi
}

# =====================================================================================
# Function: main
# Description: Main entry point for the Portainer feature script.
# =====================================================================================
main() {
    parse_arguments "$@"
    setup_portainer
    exit_script 0
}

main "$@"