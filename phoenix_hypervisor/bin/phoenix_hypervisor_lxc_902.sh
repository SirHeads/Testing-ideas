#!/bin/bash
#
# File: phoenix_hypervisor_lxc_902.sh
# Description: Finalizes the setup for LXC container 902 (BaseTemplateDocker) and creates
#              the 'docker-snapshot' ZFS snapshot. This script installs and configures
#              Docker Engine and the NVIDIA Container Toolkit, verifies their functionality,
#              and prepares the container as a template for Docker-based workloads. Comments
#              are optimized for Retrieval Augmented Generation (RAG), facilitating effective
#              chunking and vector database indexing.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script is a critical part of the Phoenix Hypervisor's template hierarchy,
# specifically for environments requiring Docker containerization. The 'docker-snapshot'
# ensures a consistent and pre-configured base for all subsequent Docker-dependent LXC containers.
#
# Usage:
#   ./phoenix_hypervisor_lxc_902.sh <CTID>
#
# Arguments:
#   - CTID (integer): The Container ID, which must be `902` for the BaseTemplateDocker.
#
# Requirements:
#   - Proxmox VE host environment with `pct` command available.
#   - LXC container `902` must be pre-created/cloned from BaseTemplate (CTID 900) and running.
#   - `jq` for JSON parsing (used to retrieve global configuration if needed).
#   - `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_common_docker.sh` must be present and executable.
#   - Internet access within the container for Docker and NVIDIA Container Toolkit installations.
#   - Appropriate permissions to manage LXC containers and ZFS snapshots.
#
# Exit Codes:
#   0: Success (Setup completed, snapshot created or already existed).
#   1: General error.
#   2: Invalid input arguments.
#   3: Container 902 does not exist or is not accessible.
#   4: Docker Engine/NVIDIA Container Toolkit installation/configuration failed.
#   5: Snapshot creation failed.
#   6: Container shutdown/start failed.

# --- Global Variables and Constants ---
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"
LXC_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json" # Needed for global NVIDIA settings
HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json" # Needed for global NVIDIA settings

# --- Logging Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] phoenix_hypervisor_lxc_902.sh: $*" | tee -a "$MAIN_LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] phoenix_hypervisor_lxc_902.sh: $*" | tee -a "$MAIN_LOG_FILE" >&2
}

# --- Exit Function ---
exit_script() {
    local exit_code=$1
    if [ "$exit_code" -eq 0 ]; then
        log_info "Script completed successfully."
    else
        log_error "Script failed with exit code $exit_code."
    fi
    exit "$exit_code"
}

# --- Script Variables ---
CTID=""
SNAPSHOT_NAME="docker-snapshot" # Defined in requirements

# =====================================================================================
# Function: parse_arguments
# Description: Parses and validates the command-line arguments, expecting a single
#              argument representing the Container ID (CTID).
#
# Parameters:
#   - $@: All command-line arguments.
#
# Global Variables Modified:
#   - `CTID`: Stores the Container ID extracted from the arguments.
#
# Exit Conditions:
#   - Exits with code 2 if an incorrect number of arguments is provided.
#
# RAG Keywords: argument parsing, command-line interface, script input, CTID.
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$(echo "$1" | xargs)" # Trim whitespace
    log_info "Received CTID: '$CTID'"
}

# =====================================================================================
# Function: validate_inputs
# Description: Validates the provided Container ID (CTID) to ensure it is a positive
#              integer and, specifically, that it matches `902` as this script is
#              tailored for the BaseTemplateDocker. A warning is logged if the CTID is not 902.
#
# Parameters: None (operates on global script variable `CTID`)
#
# Exit Conditions:
#   - Exits with code 2 if `CTID` is not a valid positive integer.
#
# RAG Keywords: input validation, CTID validation, BaseTemplateDocker, script specificity.
# =====================================================================================
validate_inputs() {
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_error "FATAL: Invalid CTID '$CTID'. Must be a positive integer."
        exit_script 2
    fi
    if [ "$CTID" -ne 902 ]; then
        log_error "WARNING: This script is specifically designed for CTID 902 (BaseTemplateDocker). Proceeding, but verify usage."
    fi
    log_info "Input validation passed."
}

# =====================================================================================
# Function: check_container_exists
# Description: Verifies the existence and manageability of the target LXC container
#              (CTID 902). This is a crucial sanity check before proceeding with
#              any Docker-specific configuration or snapshot operations.
#
# Parameters: None (operates on global script variable `CTID`)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct status`).
#
# Exit Conditions:
#   - Exits with code 3 if the container does not exist or is not accessible.
#
# RAG Keywords: container existence, LXC status, BaseTemplateDocker, Proxmox `pct`, error handling.
# =====================================================================================
check_container_exists() {
    log_info "Checking for existence of container CTID: $CTID"
    if ! pct status "$CTID" > /dev/null 2>&1; then
        log_error "FATAL: Container $CTID does not exist or is not accessible."
        exit_script 3
    fi
    log_info "Container $CTID exists."
}

# =====================================================================================
# Function: check_if_snapshot_exists
# Description: Checks if the 'docker-snapshot' ZFS snapshot already exists for the
#              target container (CTID 902). This function ensures idempotency,
#              preventing redundant snapshot creation if the setup was previously completed.
#
# Parameters: None (operates on global script variables `CTID` and `SNAPSHOT_NAME`)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct snapshot list`).
#   - `grep`: Used for parsing snapshot list output.
#
# Exit Conditions:
#   - Exits with code 0 if the 'docker-snapshot' already exists.
#   - Continues execution if the snapshot does not exist.
#
# RAG Keywords: ZFS snapshot, idempotency, Docker template, container state, Proxmox `pct`.
# =====================================================================================
check_if_snapshot_exists() {
    log_info "Checking if snapshot '$SNAPSHOT_NAME' already exists for container '$CTID'."
    log_info "Executing: pct snapshot list '$CTID'"
    if pct snapshot list "$CTID" | grep -q "$SNAPSHOT_NAME"; then
        log_info "Snapshot '$SNAPSHOT_NAME' already exists for container '$CTID'. Skipping setup."
        exit_script 0
    else
        log_info "Snapshot '$SNAPSHOT_NAME' does not exist. Proceeding with setup."
    fi
}

# =====================================================================================
# Function: install_and_configure_docker_in_container
# Description: Orchestrates the installation and configuration of Docker Engine and
#              the NVIDIA Container Toolkit within the BaseTemplateDocker container (CTID 902).
#              It delegates the core installation logic to a common Docker script,
#              passing a "none" role for Portainer as this is a base template.
#
# Parameters: None (operates on global script variable `CTID`)
#
# Dependencies:
#   - `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_common_docker.sh`: The common script for Docker setup.
#
# Exit Conditions:
#   - Exits with code 4 if the common Docker script is missing/not executable or if the Docker setup fails.
#
# RAG Keywords: Docker installation, NVIDIA Container Toolkit, LXC container,
#               BaseTemplateDocker, common script, error handling.
# =====================================================================================
install_and_configure_docker_in_container() {
    log_info "Starting Docker Engine/NVIDIA Container Toolkit setup inside container CTID: $CTID"
    local docker_script="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_common_docker.sh"

    if [ ! -f "$docker_script" ] || [ ! -x "$docker_script" ]; then
        log_error "FATAL: Common Docker script not found or not executable: $docker_script"
        exit_script 4
    fi

    # For CTID 902, portainer_role is "none" as it's a base template for Docker
    local portainer_role="none"
    local portainer_server_ip="" # Not needed for role "none"
    local portainer_agent_port="" # Not needed for role "none"

    log_info "Executing common Docker setup script for CTID $CTID with PORTAINER_ROLE=$portainer_role..."
    "$docker_script" "$CTID" "none"
    local exit_status=$?

    if [ "$exit_status" -ne 0 ]; then
        log_error "FATAL: Common Docker setup script failed for CTID $CTID with exit code $exit_status."
        exit_script 4
    fi
    log_info "Docker Engine/NVIDIA Container Toolkit setup completed successfully inside container $CTID."
}

# =====================================================================================
# Function: verify_docker_setup_inside_container
# Description: Verifies the successful installation and configuration of Docker Engine
#              and the NVIDIA Container Toolkit within the specified LXC container (CTID).
#              It executes `docker info` and an optional `hello-world` test to confirm
#              Docker's operational status.
#
# Parameters: None (operates on global script variable `CTID`)
#
# Dependencies:
#   - `pct exec`: For executing commands inside the LXC container.
#   - `docker`: Docker CLI, expected to be available in the container.
#
# Exit Conditions:
#   - Exits with code 4 if the `docker info` command fails, indicating a problem with the Docker setup.
#   - Logs a warning if the `docker run hello-world` test fails, but continues execution.
#
# RAG Keywords: Docker verification, container runtime, `docker info`, `hello-world` test,
#               LXC container, error handling, diagnostic.
# =====================================================================================
verify_docker_setup_inside_container() {
    log_info "Verifying Docker setup inside container CTID: $CTID."
    local docker_info_output
    if ! docker_info_output=$(pct exec "$CTID" -- docker info 2>&1); then
        log_error "FATAL: Docker setup verification failed for CTID $CTID. 'docker info' command failed."
        echo "$docker_info_output" | log_error # Log the output of docker info for debugging
        exit_script 4
    fi
    log_info "Docker setup verification successful for CTID $CTID. docker info output:"
    echo "$docker_info_output" | while IFS= read -r line; do log_info "$line"; done

    log_info "Running docker hello-world test inside container $CTID..."
    local hello_world_output
    if ! hello_world_output=$(pct exec "$CTID" -- docker run --rm hello-world 2>&1); then
        log_error "WARNING: Docker hello-world test failed for CTID $CTID."
        echo "$hello_world_output" | log_error
    else
        log_info "Docker hello-world test successful for CTID $CTID."
        echo "$hello_world_output" | while IFS= read -r line; do log_info "$line"; done
    fi
}

# =====================================================================================
# Function: shutdown_container
# Description: Safely shuts down the specified LXC container (CTID). It initiates
#              the shutdown process using `pct shutdown` and then polls the container's
#              status until it reaches a 'stopped' state or a timeout occurs.
#
# Parameters:
#   - $1 (CTID): The Container ID of the LXC container to shut down.
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct shutdown`, `pct status`).
#
# Exit Conditions:
#   - Exits with code 6 if the shutdown initiation fails or if the container
#     does not stop within the defined timeout.
#
# RAG Keywords: container shutdown, LXC management, Proxmox `pct`, graceful shutdown,
#               timeout, error handling.
# =====================================================================================
# =====================================================================================
shutdown_container() {
    local ctid="$1"
    local timeout=60 # seconds
    local interval=3 # seconds
    local elapsed_time=0

    log_info "Initiating shutdown of container $ctid..."
    if ! pct shutdown "$ctid"; then
        log_error "FATAL: Failed to initiate shutdown for container $ctid."
        exit_script 6
    fi

    log_info "Waiting for container $ctid to stop..."
    while [ "$elapsed_time" -lt "$timeout" ]; do
        if pct status "$ctid" | grep -q "status: stopped"; then
            log_info "Container $ctid is stopped."
            return 0
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    log_error "FATAL: Container $ctid did not stop within ${timeout} seconds."
    exit_script 6
}

# =====================================================================================
# Function: create_docker_snapshot
# Description: Creates the 'docker-snapshot' ZFS snapshot for the specified LXC container
#              (CTID 902). This snapshot captures the state of the BaseTemplateDocker
#              after Docker Engine and NVIDIA Container Toolkit have been successfully
#              integrated, making it ready for cloning into Docker-enabled LXC containers.
#
# Parameters: None (operates on global script variables `CTID` and `SNAPSHOT_NAME`)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct snapshot create`).
#
# Exit Conditions:
#   - Exits with code 5 if the snapshot creation fails.
#
# RAG Keywords: ZFS snapshot, Docker template, container imaging, Docker integration,
#               Proxmox `pct`, error handling.
# =====================================================================================
create_docker_snapshot() {
    log_info "Creating ZFS snapshot '$SNAPSHOT_NAME' for container '$CTID'..."
    log_info "Executing: pct snapshot '${CTID}' '${SNAPSHOT_NAME}'"
    if ! pct snapshot "${CTID}" "${SNAPSHOT_NAME}"; then
        log_error "FATAL: Failed to create snapshot '$SNAPSHOT_NAME' for container '$CTID'."
        exit_script 5
    fi
    log_info "Snapshot '$SNAPSHOT_NAME' created successfully for container '$CTID'."
}

# =====================================================================================
# Function: start_container
# Description: Restarts the specified LXC container (CTID) after the ZFS snapshot
#              has been successfully created. It initiates the startup using `pct start`
#              and then polls the container's status until it reaches a 'running' state
#              or a timeout occurs.
#
# Parameters:
#   - $1 (CTID): The Container ID of the LXC container to start.
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct start`, `pct status`).
#
# Exit Conditions:
#   - Exits with code 6 if the startup initiation fails or if the container
#     does not start within the defined timeout.
#
# RAG Keywords: container startup, LXC management, Proxmox `pct`, container restart,
#               timeout, error handling.
# =====================================================================================
start_container() {
    local ctid="$1"
    local timeout=60 # seconds
    local interval=3 # seconds
    local elapsed_time=0

    log_info "Starting container $ctid after snapshot creation..."
    if ! pct start "$ctid"; then
        log_error "FATAL: Failed to start container $ctid."
        exit_script 6
    fi

    log_info "Waiting for container $ctid to start..."
    while [ "$elapsed_time" -lt "$timeout" ]; do
        if pct status "$ctid" | grep -q "status: running"; then
            log_info "Container $ctid is running."
            return 0
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    log_error "FATAL: Container $ctid did not start within ${timeout} seconds."
    exit_script 6
}

# =====================================================================================
# Function: main
# Description: The main entry point for the BaseTemplateDocker (CTID 902) setup script.
#              It orchestrates the entire process of preparing the Docker-enabled template,
#              including argument parsing, input validation, checking for existing
#              snapshots, installing and verifying Docker components, shutting down,
#              creating the 'docker-snapshot', and restarting the container.
#
# Parameters:
#   - $@: All command-line arguments passed to the script.
#
# Dependencies:
#   - `parse_arguments()`
#   - `validate_inputs()`
#   - `check_container_exists()`
#   - `check_if_snapshot_exists()`
#   - `install_and_configure_docker_in_container()`
#   - `verify_docker_setup_inside_container()`
#   - `shutdown_container()`
#   - `create_docker_snapshot()`
#   - `start_container()`
#   - `exit_script()`
#
# RAG Keywords: main function, script entry point, BaseTemplateDocker setup, ZFS snapshot,
#               Docker configuration, LXC management.
# =====================================================================================
# =====================================================================================
main() {
    parse_arguments "$@"
    validate_inputs
    check_container_exists
    check_if_snapshot_exists # Exits 0 if snapshot already exists

    install_and_configure_docker_in_container
    verify_docker_setup_inside_container
    shutdown_container "$CTID"
    create_docker_snapshot
    start_container "$CTID"

    exit_script 0
}

# Call the main function
main "$@"