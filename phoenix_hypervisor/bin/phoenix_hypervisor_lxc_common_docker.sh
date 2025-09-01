#!/bin/bash
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
source "$(dirname "$0")/phoenix_hypervisor_lxc_common_loghelpers.sh"

# Add a diagnostic log to confirm the settings
# --- Global Configuration Variables ---
# These variables define paths to configuration files and log files used throughout the script.
HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] phoenix_hypervisor_lxc_common_docker.sh: LANG is set to: $LANG" | tee -a "$MAIN_LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] phoenix_hypervisor_lxc_common_docker.sh: LC_ALL is set to: $LC_ALL" | tee -a "$MAIN_LOG_FILE"

#
# phoenix_hypervisor/bin/phoenix_hypervisor_lxc_common_docker.sh
#
# ## Script Overview
# This script automates the installation and configuration of Docker Engine and the NVIDIA Container Toolkit
# within a specified Proxmox LXC container. It also handles the deployment and integration
# of Portainer (either as a server or an agent) to manage Docker environments.
#
# ## Version
# 0.1.0
#
# ## Author
# Heads, Qwen3-coder (AI Assistant)
#
# ## Key Features
# - Installs Docker Engine and its dependencies.
# - Configures the NVIDIA Container Toolkit for GPU passthrough in Docker.
# - Manages user groups for Docker access.
# - Deploys and configures Portainer Server or Agent.
# - Includes idempotency checks to prevent redundant installations.
#
# ## Usage
# To execute this script, provide the Container ID (CTID) and Portainer role
# as environment variables, followed by the CTID as a command-line argument.
#
# ### Arguments:
# - `$1` (CTID): (Required) The ID of the LXC container.
# - `$2` (PORTAINER_ROLE): (Required) Specifies the Portainer deployment role.
#   - `server`: Deploys Portainer Server.
#   - `agent`: Deploys Portainer Agent, requiring `PORTAINER_SERVER_IP` and `PORTAINER_AGENT_PORT`.
#   - `none`: Skips Portainer deployment.
# - `PORTAINER_SERVER_IP`: (Required for `agent` role) IP address of the Portainer Server.
# - `PORTAINER_AGENT_PORT`: (Required for `agent` role) Port for the Portainer Agent to connect to the server.
#
# ### Example Command:
# ```bash
# CTID=101 PORTAINER_ROLE="agent" PORTAINER_SERVER_IP="10.0.0.99" PORTAINER_AGENT_PORT="9001" ./phoenix_hypervisor_lxc_common_docker.sh 101
# ```
#
# ## Requirements
# - Proxmox host environment with `pct` command available.
# - Target LXC container must be running a Debian-based OS (e.g., Ubuntu) with `curl` and `apt-get`.
#
# ## Exit Codes
# - `0`: Script completed successfully.
# - `1`: General error or unhandled exception.
# - `2`: Invalid input parameters or missing environment variables.
# - `3`: Target LXC container does not exist.
# - `4`: Docker installation or configuration failed.
# - `5`: Portainer setup or deployment failed.


# --- Script Exit Handler ---
# Manages script exit, logging the final status based on the exit code.

# exit_script: Exits the script with a specified status code.
# Arguments:
#   $1: The exit code (0 for success, non-zero for failure).
exit_script() {
    local exit_code=$1
    if [ "$exit_code" -eq 0 ]; then
        log_info "Script completed successfully."
    else
        log_error "Script failed with exit code $exit_code."
    fi
    exit "$exit_code"
}

# =====================================================================================
# ## Function: wait_for_portainer_ready
# ### Description
# Polls a given Portainer URL inside the target LXC container until it returns a healthy HTTP status
# (200, 302, 401, or 403) or a predefined timeout is reached. This function is crucial
# for ensuring that the Portainer container (server or agent) is fully initialized and
# accessible before proceeding with subsequent operations.
#
# ### Arguments
# - `$1` (CTID): The Container ID of the LXC.
# - `$2` (container_name): The name of the Portainer Docker container (e.g., "portainer", "portainer_agent").
# - `$3` (portainer_url): The URL to poll for Portainer's readiness status.
#
# ### Behavior
# - Logs informational messages during polling and upon success or timeout.
# - Uses `pct exec` to run `curl` inside the container, checking the HTTP status code.
# - Retries polling at regular intervals until the timeout is exceeded.
#
# ### Exit Codes
# - `0`: Portainer container is ready.
# - `1`: Timeout reached, Portainer container did not become ready.
# =====================================================================================
wait_for_portainer_ready() {
    local ctid="$1"
    local container_name="$2"
    local portainer_url="$3"
    local timeout=60 # seconds
    local interval=5 # seconds
    local elapsed_time=0

    log_info "Waiting for Portainer container '$container_name' at '$portainer_url' to be ready (CTID: $ctid)..."

    while [ "$elapsed_time" -lt "$timeout" ]; do
        http_code=$(pct exec "$ctid" -- curl -k -s -o /dev/null -w "%{http_code}" "$portainer_url")
        if [[ "$http_code" == "200" || "$http_code" == "302" || "$http_code" == "401" || "$http_code" == "403" ]]; then
            log_info "Portainer container '$container_name' at '$portainer_url' is ready (HTTP $http_code)."
            return 0
        fi
        log_info "Portainer container '$container_name' not yet ready (HTTP $http_code). Retrying in $interval seconds..."
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    log_error "Timeout: Portainer container '$container_name' at '$portainer_url' did not become ready within $timeout seconds."
    return 1
}


# =====================================================================================
# ## Function: parse_arguments
# ### Description
# Parses command-line arguments to extract the Container ID (CTID).
# This function ensures that the script receives the necessary CTID to target the correct LXC container.
#
# ### Arguments
# - `$@`: All command-line arguments passed to the script.
#
# ### Behavior
# - Expects exactly one argument, which is the CTID.
# - If the argument count is incorrect, logs a usage error and exits.
# - Assigns the first argument to the global `CTID` variable.
#
# ### Exit Codes
# - `0`: Arguments parsed successfully.
# - `2`: Invalid number of arguments provided.
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 2 ]; then
        log_error "Usage: $0 <CTID> <PORTAINER_ROLE>"
        log_error "Received arguments: $*"
        log_error "Expected 2 arguments, got $#."
        exit_script 2
    fi
    CTID="$1"
    PORTAINER_ROLE="$2"
    log_info "Received CTID: $CTID"
    log_info "Received PORTAINER_ROLE: $PORTAINER_ROLE"
}

# =====================================================================================
# ## Function: validate_inputs
# ### Description
# Validates all essential inputs for the script, including the Container ID (CTID)
# and environment variables related to Portainer deployment. This ensures that
# the script operates with valid and complete parameters, preventing runtime errors.
#
# ### Validations Performed
# - **CTID**: Must be a positive integer.
# - **PORTAINER_ROLE**: Must be set and one of "server", "agent", or "none".
# - **PORTAINER_SERVER_IP**: Required if `PORTAINER_ROLE` is "agent".
# - **PORTAINER_AGENT_PORT**: Required if `PORTAINER_ROLE` is "agent".
#
# ### Behavior
# - Logs fatal errors and exits the script if any validation fails.
# - Logs successful validation upon completion.
#
# ### Exit Codes
# - `0`: All inputs are valid.
# - `2`: Invalid CTID or missing/invalid environment variables.
# =====================================================================================
validate_inputs() {
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_error "FATAL: Invalid CTID '$CTID'. Must be a positive integer."
        exit_script 2
    fi
    if ! [[ "$PORTAINER_ROLE" =~ ^(server|agent|none)$ ]]; then
        log_error "FATAL: Invalid PORTAINER_ROLE '$PORTAINER_ROLE'. Must be 'server', 'agent', or 'none'."
        exit_script 2
    fi
    if [ "$PORTAINER_ROLE" == "agent" ]; then
        if [ -z "$PORTAINER_SERVER_IP" ] || [ -z "$PORTAINER_AGENT_PORT" ]; then
            log_error "FATAL: PORTAINER_SERVER_IP and PORTAINER_AGENT_PORT must be set for Portainer agent role."
            exit_script 2
        fi
    fi
    log_info "Input validation passed."
}

# =====================================================================================
# ## Function: check_container_exists
# ### Description
# Verifies the existence of the target LXC container using its Container ID (CTID).
# This is a critical preliminary check to ensure that subsequent operations are
# performed on a valid and existing container.
#
# ### Arguments
# - None (uses global `CTID`).
#
# ### Behavior
# - Uses `pct status` to check the container's status.
# - Logs a fatal error and exits if the container does not exist.
# - Logs confirmation if the container is found.
#
# ### Exit Codes
# - `0`: Container exists.
# - `3`: Container does not exist.
# =====================================================================================
check_container_exists() {
    log_info "Checking for existence of container CTID: $CTID"
    if ! pct status "$CTID" > /dev/null 2>&1; then
        log_error "FATAL: Container $CTID does not exist."
        exit_script 3
    fi
    log_info "Container $CTID exists."
}

# =====================================================================================
# ## Function: install_and_configure_docker_in_container
# ### Description
# Orchestrates the complete installation and configuration of Docker Engine,
# NVIDIA Container Toolkit, and Portainer (server or agent) within a specified
# Proxmox LXC container. This function includes robust idempotency checks to
# ensure that components are only installed or configured if necessary.
#
# ### Arguments
# - None (uses global `CTID`, `PORTAINER_ROLE`, `PORTAINER_SERVER_IP`, `PORTAINER_AGENT_PORT`).
#
# ### Key Steps
# 1.  **Idempotency Check**: Determines if Docker, NVIDIA Toolkit, and Portainer are already configured.
# 2.  **Add Docker Repository**: Adds the official Docker APT repository to the container.
# 3.  **Install Docker Engine & Compose Plugin**: Installs core Docker components.
# 4.  **Install NVIDIA Container Toolkit**: Installs the necessary components for GPU support.
# 5.  **Configure Docker Daemon**: Sets up the Docker daemon to use the NVIDIA runtime.
# 6.  **User Group Management**: Adds the default user to the `docker` group.
# 7.  **Start Docker Service**: Enables and starts the Docker systemd service.
# 8.  **Portainer Integration**: Deploys and configures Portainer Server or Agent based on `PORTAINER_ROLE`.
# 9.  **Final Verification**: Performs a `docker info` check to confirm successful installation.
#
# ### Exit Codes
# - `0`: Docker and Portainer (if applicable) installed and configured successfully.
# - `4`: Docker installation or configuration failed at any step.
# - `5`: Portainer setup or deployment failed.
# =====================================================================================
install_and_configure_docker_in_container() {
    log_info "Installing and configuring Docker in container CTID: $CTID"

    local default_user="ubuntu" # Assuming Ubuntu base image for LXC.
    local docker_daemon_config_file="/etc/docker/daemon.json"
    local nvidia_runtime_config='{ "default-runtime": "nvidia", "runtimes": { "nvidia": { "path": "/usr/bin/nvidia-container-runtime", "runtimeArgs": [] } } }'
    local portainer_server_image="portainer/portainer-ce:latest"
    local portainer_agent_image=$(jq -r '.docker.portainer_agent_image' "$HYPERVISOR_CONFIG_FILE")

    log_debug "DEBUG: portainer_server_image: $portainer_server_image"
    log_debug "DEBUG: portainer_agent_image: $portainer_agent_image"

    # --- Idempotency Check ---
    # Checks if Docker, NVIDIA Container Toolkit, and the specified Portainer container
    # are already installed and running. If all conditions are met, the installation
    # process is skipped to ensure efficiency and prevent redundant operations.
    log_info "Performing idempotency check for Docker and Portainer components..."
    local docker_installed=false
    if pct exec "$CTID" -- command -v docker > /dev/null 2>&1 && \
       pct exec "$CTID" -- systemctl is-active docker > /dev/null 2>&1 && \
       pct exec "$CTID" -- groups "$default_user" | grep -q docker; then
        docker_installed=true
        log_info "Docker Engine appears to be installed and running."
    else
        log_info "Docker Engine not fully installed or running. Proceeding with installation."
    fi

    local nvidia_toolkit_installed=false
    if pct exec "$CTID" -- dpkg -l | grep -q nvidia-container-toolkit; then
        nvidia_toolkit_installed=true
        log_info "NVIDIA Container Toolkit appears to be installed."
    else
        log_info "NVIDIA Container Toolkit not installed. Proceeding with installation."
    fi

    local portainer_running=false
    if [ "$PORTAINER_ROLE" == "server" ]; then
        if pct exec "$CTID" -- docker ps --filter "name=^portainer$" --format "{{.Names}}" | grep -q "^portainer$"; then
            portainer_running=true
            log_info "Portainer Server container is running."
        fi
    elif [ "$PORTAINER_ROLE" == "agent" ]; then
        if pct exec "$CTID" -- docker ps --filter "name=^portainer_agent$" --format "{{.Names}}" | grep -q "^portainer_agent$"; then
            portainer_running=true
            log_info "Portainer Agent container is running."
        fi
    fi

    if $docker_installed && $nvidia_toolkit_installed && ([ "$PORTAINER_ROLE" == "none" ] || $portainer_running); then
        log_info "All required Docker and Portainer components are already correctly configured. Skipping installation."
        return 0
    fi

    # Generate and set the locale to en_US.UTF-8
    log_info "Generating and setting locale to en_US.UTF-8 inside the container (CTID: $CTID)..."
    if ! pct exec "$CTID" -- bash -c "apt-get update && apt-get install -y locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8"; then
        log_error "FATAL: Failed to generate and set en_US.UTF-8 locale."
        exit_script 4
    fi
    log_info "Locale en_US.UTF-8 generated and set successfully."

    # --- Add Docker Official Repository ---
    # Adds the official Docker APT repository to the LXC container's package sources.
    # This ensures that the latest stable versions of Docker components can be installed.
    log_info "Adding Docker official repository inside the container (CTID: $CTID)..."
    if ! pct exec "$CTID" -- apt-get update; then log_error "Failed to update apt package list." && exit_script 4; fi
    if ! pct exec "$CTID" -- apt-get install -y ca-certificates curl gnupg lsb-release; then log_error "Failed to install Docker repository prerequisites." && exit_script 4; fi
    if ! pct exec "$CTID" -- mkdir -p /etc/apt/keyrings; then log_error "Failed to create /etc/apt/keyrings directory." && exit_script 4; fi
    # Remove existing Docker GPG key to prevent overwrite prompts
    if pct exec "$CTID" -- [ -f /etc/apt/keyrings/docker.gpg ]; then
        log_info "Removing existing /etc/apt/keyrings/docker.gpg"
        if ! pct exec "$CTID" -- rm /etc/apt/keyrings/docker.gpg; then log_error "Failed to remove existing Docker GPG key." && exit_script 4; fi
    fi
    if ! pct exec "$CTID" -- bash -c "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"; then log_error "Failed to download Docker GPG key." && exit_script 4; fi
    if ! pct exec "$CTID" -- chmod a+r /etc/apt/keyrings/docker.gpg; then log_error "Failed to set permissions on Docker GPG key." && exit_script 4; fi
    if ! pct exec "$CTID" -- bash -c "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null"; then log_error "Failed to add Docker repository to sources.list.d." && exit_script 4; fi
    if ! pct exec "$CTID" -- apt-get update; then log_error "Failed to update apt package list after adding Docker repo." && exit_script 4; fi
    log_info "Docker official repository added successfully."

    # --- Install Docker Engine & Compose Plugin ---
    # Installs the core Docker Engine, CLI, containerd, and the Docker Compose plugin.
    log_info "Installing Docker Engine, CLI, containerd, and Docker Compose Plugin (CTID: $CTID)..."
    if ! pct exec "$CTID" -- apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
        log_error "FATAL: Failed to install Docker Engine and Compose Plugin."
        exit_script 4
    fi
    log_info "Docker Engine and Compose Plugin installed successfully."


    # --- Install NVIDIA Container Toolkit ---
    # Installs the NVIDIA Container Toolkit, which enables Docker containers to
    # access NVIDIA GPUs within the LXC environment.
    log_info "Installing NVIDIA Container Toolkit (CTID: $CTID)..."
    if ! pct exec "$CTID" -- apt-get install -y nvidia-container-toolkit; then
        log_error "FATAL: Failed to install NVIDIA Container Toolkit. Ensure NVIDIA repository is configured if GPU support is required."
        exit_script 4
    fi
    log_info "NVIDIA Container Toolkit installed successfully."
    log_info "Creating NVIDIA Container Toolkit config file..."
    local toolkit_config_content="[nvidia-container-cli]\ndriver-root = \"/usr/lib/x86_64-linux-gnu/nvidia/current\"\n"
    if ! pct exec "$CTID" -- bash -c "mkdir -p /etc/nvidia-container-runtime && echo -e \"$toolkit_config_content\" > /etc/nvidia-container-runtime/config.toml"; then
        log_error "FATAL: Failed to create NVIDIA Container Toolkit config file."
        exit_script 4
    fi

    # --- Configure Docker Daemon for NVIDIA Runtime ---
    # Modifies the Docker daemon configuration to set NVIDIA as the default runtime.
    # This is essential for Docker containers to utilize NVIDIA GPUs.
    log_info "Configuring Docker daemon for NVIDIA runtime (CTID: $CTID)..."
    if ! pct exec "$CTID" -- mkdir -p "$(dirname "$docker_daemon_config_file")"; then log_error "Failed to create Docker daemon config directory." && exit_script 4; fi
    if ! pct exec "$CTID" -- bash -c "echo '$nvidia_runtime_config' > '$docker_daemon_config_file'"; then
        log_error "FATAL: Failed to write Docker daemon configuration for NVIDIA runtime."
        exit_script 4
    fi
    log_info "Docker daemon configured for NVIDIA runtime. Restarting Docker service..."
    if ! pct exec "$CTID" -- systemctl restart docker; then
        log_error "FATAL: Failed to restart Docker service after daemon.json configuration."
        exit_script 4
    fi
    log_info "Docker service restarted successfully."

    # --- User Group Management ---
    # Ensures the default user (`ubuntu`) exists and adds it to the `docker` group.
    # This allows the user to run Docker commands without `sudo`.
    log_info "Ensuring user '$default_user' exists and adding to the docker group (CTID: $CTID)..."
    if ! pct exec "$CTID" -- id -u "$default_user" > /dev/null 2>&1; then
        log_info "User '$default_user' does not exist. Creating user..."
        if ! pct exec "$CTID" -- useradd -m -s /bin/bash "$default_user"; then
            log_error "FATAL: Failed to create user '$default_user'."
            exit_script 4
        fi
        log_info "User '$default_user' created successfully."
    fi
    if ! pct exec "$CTID" -- usermod -aG docker "$default_user"; then
        log_error "FATAL: Failed to add user '$default_user' to the docker group."
        exit_script 4
    fi
    log_info "User '$default_user' added to docker group."

    # --- Start Docker Service ---
    # Enables and starts the Docker systemd service within the container.
    # Verifies that the service is active after startup.
    log_info "Starting and enabling Docker service (CTID: $CTID)..."
    if ! pct exec "$CTID" -- systemctl enable docker --now; then
        log_error "FATAL: Failed to start and enable Docker service."
        exit_script 4
    fi
    if ! pct exec "$CTID" -- systemctl is-active docker > /dev/null 2>&1; then
        log_error "FATAL: Docker service is not active after starting."
        exit_script 4
    fi
    log_info "Docker service started and enabled successfully."

    # --- Portainer Integration ---
    # Deploys either Portainer Server or Portainer Agent as a Docker container,
    # based on the `PORTAINER_ROLE` environment variable.
    if [ "$PORTAINER_ROLE" == "server" ]; then
        log_info "Setting up Portainer Server container (CTID: $CTID)..."
        if ! pct exec "$CTID" -- docker volume create portainer_data; then log_error "Failed to create portainer_data volume." && exit_script 5; fi
        local portainer_server_docker_command="docker run -d -p 9443:9443 -p 9001:9001 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data \"$portainer_server_image\""
        if ! pct exec "$CTID" -- bash -c "$portainer_server_docker_command"; then
            log_error "FATAL: Failed to run Portainer Server container."
            exit_script 5
        fi
        local portainer_server_url="https://localhost:9443"
        if ! wait_for_portainer_ready "$CTID" "portainer" "$portainer_server_url"; then
            log_error "FATAL: Portainer Server did not become ready within the timeout."
            exit_script 5
        fi
        log_info "Portainer Server container deployed and ready."
    elif [ "$PORTAINER_ROLE" == "agent" ]; then
        log_info "Setting up Portainer Agent container (CTID: $CTID)..."
        local agent_cluster_addr="tcp://${PORTAINER_SERVER_IP}:${PORTAINER_AGENT_PORT}"
        local portainer_agent_url="http://localhost:9999/status" # Default agent status endpoint for readiness check.
        if ! pct exec "$CTID" -- docker volume create portainer_agent_data; then log_error "Failed to create portainer_agent_data volume." && exit_script 5; fi
        local portainer_agent_docker_command="docker run -d --name portainer_agent --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker/volumes:/var/lib/docker/volumes -v portainer_agent_data:/data -e AGENT_CLUSTER_ADDR=\"$agent_cluster_addr\" \"$portainer_agent_image\""
        if ! pct exec "$CTID" -- bash -c "$portainer_agent_docker_command"; then
            log_error "FATAL: Failed to run Portainer Agent container."
            exit_script 5
        fi
        if ! wait_for_portainer_ready "$CTID" "portainer_agent" "$portainer_agent_url"; then
            log_error "FATAL: Portainer Agent did not become ready within the timeout."
            exit_script 5
        fi
        log_info "Portainer Agent container deployed and ready."
    else
        log_info "Portainer role is 'none', skipping Portainer container setup."
    fi

    # --- Final Verification ---
    # Executes `docker info` inside the container to confirm that Docker is
    # fully operational and correctly configured after all installation steps.
    log_info "Performing final verification of Docker installation (CTID: $CTID)..."
    if ! pct exec "$CTID" -- docker info; then
        log_error "FATAL: 'docker info' command failed after installation. Review logs for details."
        exit_script 4
    fi
    log_info "Docker Engine and Portainer configuration complete for CTID: $CTID."
}

# =====================================================================================
# ## Function: main
# ### Description
# The main entry point of the script. It orchestrates the execution flow by
# calling all necessary functions in sequence to install and configure Docker
# and Portainer within the specified LXC container.
#
# ### Execution Flow
# 1.  `parse_arguments`: Extracts the CTID from command-line arguments.
# 2.  `validate_inputs`: Validates all script inputs and environment variables.
# 3.  `check_container_exists`: Confirms the target LXC container is present.
# 4.  `install_and_configure_docker_in_container`: Performs the core installation and setup.
# 5.  `exit_script`: Handles the final script exit status.
#
# ### Arguments
# - `$@`: All command-line arguments passed to the script.
#
# ### Exit Codes
# - `0`: Script executed successfully.
# - Non-zero: Indicates failure from one of the called sub-functions.
# =====================================================================================
main() {
    parse_arguments "$@"
    validate_inputs
    check_container_exists
    install_and_configure_docker_in_container
    exit_script 0
}

# Call the main function
main "$@"
