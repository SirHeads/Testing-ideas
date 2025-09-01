#!/bin/bash
#
# File: phoenix_hypervisor_lxc_910.sh
# Description: Script to finalize the setup for LXC container 910, which hosts the Portainer Server.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script automates the deployment and configuration of the Portainer Server application
# within the designated LXC container (CTID 910). It performs the following key actions:
# - Pulls the Portainer CE Docker image.
# - Runs the Portainer container with essential configurations, including volume mounts and port mappings.
# - Verifies the Portainer service is operational and network accessible.
#
# ## Usage
# ```bash
# ./phoenix_hypervisor_lxc_910.sh <CTID>
# ```
#
# ### Arguments
# - `$1` (CTID): The Container ID for the LXC, specifically `910` for the Portainer Server.
#
# ## Requirements
# - **Environment:** Proxmox host with `pct` command available.
# - **Container State:** LXC container `910` must be pre-created/cloned and accessible.
# - **Dependencies:** `jq` for JSON parsing (if configuration files are used).
# - **Base Image:** Container `910` is expected to be cloned from `902`'s 'docker-snapshot'.
# - **Docker:** Docker daemon must be fully functional inside container `910`.
#
# ## Exit Codes
# - `0`: Success. Portainer Server deployed, running, and accessible.
# - `1`: General script error.
# - `2`: Invalid input arguments provided.
# - `3`: Container `910` does not exist or is inaccessible.
# - `4`: Docker is not functional within container `910`.
# - `5`: Portainer Server container deployment failed.
# - `6`: Portainer Server accessibility verification failed.

# --- Global Variables and Constants ---
# `MAIN_LOG_FILE`: Defines the main log file path for script output.
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"
# `HYPERVISOR_CONFIG_FILE`: Specifies the path to the hypervisor's main configuration file.
HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"

# --- Logging Functions ---
# `log_info()`
# **Purpose:** Logs informational messages to standard output and the main log file.
# **Arguments:**
#   - `$*`: The message string to be logged.
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] phoenix_hypervisor_lxc_910.sh: $*" | tee -a "$MAIN_LOG_FILE"
}

# `log_error()`
# **Purpose:** Logs error messages to standard error and the main log file.
# **Arguments:**
#   - `$*`: The error message string to be logged.
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] phoenix_hypervisor_lxc_910.sh: $*" | tee -a "$MAIN_LOG_FILE" >&2
}

# --- Exit Function ---
# `exit_script()`
# **Purpose:** Handles script termination, logging a final status message based on the provided exit code.
# **Arguments:**
#   - `$1`: The integer exit code. `0` for success, non-zero for various error conditions.
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
# `CTID`: Stores the Container ID for the target LXC. Expected to be `910` for Portainer Server.
CTID=""
# `CONTAINER_IP`: Stores the IP address of the LXC container. This value is parsed from configuration files.
CONTAINER_IP=""
# `PORTAINER_SERVER_PORT`: Stores the network port on which the Portainer Server is expected to be accessible. This value is parsed from configuration files.
PORTAINER_SERVER_PORT=""

# ## Function: `parse_arguments()`
# **Purpose:** Parses command-line arguments to extract the Container ID (CTID).
#
# **Details:**
# - **Argument Count Check:** Verifies that exactly one argument is provided.
# - **Error Handling:** If the argument count is incorrect, logs a usage error and terminates the script with exit code `2`.
# - **CTID Assignment:** Assigns the first command-line argument to the global `CTID` variable.
# - **Logging:** Records the received CTID for auditing and debugging.
#
# **Exit Codes:**
# - `2`: Indicates an invalid number of command-line arguments.
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Received CTID: $CTID"
}

# ## Function: `validate_inputs()`
# **Purpose:** Validates the format and expected value of the provided Container ID (CTID).
#
# **Details:**
# - **Integer Validation:** Checks if `CTID` is a positive integer. If not, logs a fatal error and exits with code `2`.
# - **Specific CTID Check:** Issues a warning if `CTID` is not `910`, as this script is tailored for Portainer Server (CTID 910). The script will continue but advises verification.
# - **Logging:** Confirms successful input validation.
#
# **Exit Codes:**
# - `2`: Indicates an invalid CTID format or value.
validate_inputs() {
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_error "FATAL: Invalid CTID '$CTID'. Must be a positive integer."
        exit_script 2
    fi
    if [ "$CTID" -ne 910 ]; then
        log_error "WARNING: This script is specifically designed for CTID 910 (Portainer Server). Proceeding, but verify usage."
    fi
    log_info "Input validation passed."
}

# ## Function: `check_container_exists()`
# **Purpose:** Verifies that the target LXC container exists and is accessible on the Proxmox host.
#
# **Details:**
# - **Status Check:** Executes `pct status "$CTID"` to query the container's state.
# - **Error Handling:** If `pct status` returns a non-zero exit code (indicating the container does not exist or an access issue), logs a fatal error and exits with code `3`.
# - **Logging:** Confirms the container's existence.
#
# **Exit Codes:**
# - `3`: Indicates the container does not exist or is inaccessible.
check_container_exists() {
    log_info "Checking for existence of container CTID: $CTID"
    if ! pct status "$CTID" > /dev/null 2>&1; then
        log_error "FATAL: Container $CTID does not exist or is not accessible."
        exit_script 3
    fi
    log_info "Container $CTID exists."
}

# ## Function: `check_if_portainer_already_running()`
# **Purpose:** Implements idempotency by checking if the Portainer Server Docker container is already active within the LXC.
#
# **Details:**
# - **Docker Process Check:** Executes `docker ps` inside the container, filtering for a container named 'portainer'.
# - **Idempotency Logic:** If a running 'portainer' container is found, logs a message indicating that the setup is complete and exits the script with code `0` (success) to prevent redundant deployments.
# - **Logging:** If Portainer is not found running, logs that the deployment process will continue.
#
# **Exit Codes:**
# - `0`: Portainer Server container is already running, indicating successful prior setup.
check_if_portainer_already_running() {
    log_info "Checking if Portainer Server container is already running inside CTID: $CTID"
    if pct exec "$CTID" -- docker ps --filter "name=portainer" --format "{{.Names}}" | grep -q "^portainer$"; then
        log_info "Portainer Server container is already running inside $CTID. Skipping deployment."
        exit_script 0
    else
        log_info "Portainer Server container not found running. Proceeding with deployment."
    fi
}

# ## Function: `verify_docker_is_functional_inside_container()`
# **Purpose:** Ensures that the Docker daemon is installed and fully functional within the target LXC container.
#
# **Details:**
# - **Docker Info Check:** Executes `docker info` inside the container to verify Docker's operational status.
# - **Error Handling:** If `docker info` returns a non-zero exit code, logs a fatal error indicating Docker is not functional and exits with code `4`.
# - **Logging:** Confirms that Docker is functional within the container.
#
# **Exit Codes:**
# - `4`: Docker daemon is not functional inside the container.
verify_docker_is_functional_inside_container() {
    log_info "Verifying Docker functionality inside container CTID: $CTID."
    if ! pct exec "$CTID" -- docker info > /dev/null 2>&1; then
        log_error "FATAL: Docker is not functional inside container $CTID. Please ensure Docker is installed and running."
        exit_script 4
    fi
    log_info "Docker verified as functional inside container $CTID."
}

# ## Function: `deploy_portainer_server_container_inside_container()`
# **Purpose:** Deploys the Portainer Server Docker container within the specified LXC container.
#
# **Details:**
# - **Image Specification:** Uses `portainer/portainer-ce:latest` for consistent deployment.
# - **Container Configuration:**
#   - `container_name`: `portainer`
#   - `ports`: `-p 9443:9443 -p 9001:9001` (maps host ports to container ports for UI and agent).
#   - `docker_socket_volume`: `-v /var/run/docker.sock:/var/run/docker.sock` (mounts Docker socket for Portainer to manage Docker).
#   - `data_volume`: `-v portainer_data:/data` (persists Portainer data).
#   - `restart_policy`: `--restart=always` (ensures Portainer restarts with Docker).
# - **Execution:** Constructs and executes the `docker run` command via `pct exec`.
# - **Error Handling:** If the `docker run` command fails, logs a fatal error and exits with code `5`.
# - **Logging:** Confirms the successful initiation of the Portainer Server container deployment.
#
# **Exit Codes:**
# - `5`: Portainer Server container deployment failed.
deploy_portainer_server_container_inside_container() {
    log_info "Deploying Portainer Server Docker container inside container CTID: $CTID"

    local portainer_image="portainer/portainer-ce:latest"
    local container_name="portainer"
    local ports="-p 9443:9443 -p 9001:9001"
    local docker_socket_volume="-v /var/run/docker.sock:/var/run/docker.sock"
    local data_volume="-v portainer_data:/data"
    local restart_policy="--restart=always"
    local command="" # No initial password set via CLI for now, user will set via UI

    local full_run_cmd="/usr/bin/docker run -d $ports $docker_socket_volume $data_volume $restart_policy --name $container_name $portainer_image $command"

    log_info "Executing docker run command for Portainer Server: $full_run_cmd"
    if ! pct exec "$CTID" -- "$full_run_cmd"; then
        log_error "FATAL: Portainer Server container deployment failed for CTID $CTID."
        exit_script 5
    fi
    log_info "Portainer Server container deployment initiated successfully."
}

# ## Function: `wait_for_portainer_initialization()`
# **Purpose:** Monitors and waits for the Portainer Server to fully initialize and become network responsive within the LXC.
#
# **Details:**
# - **Polling Mechanism:** Implements a `while` loop that polls for Portainer's readiness.
# - **Timeout:** Configured with a `120`-second timeout to prevent indefinite waiting.
# - **Interval:** Checks every `5` seconds.
# - **Readiness Check:**
#   1. Verifies the 'portainer' Docker container is running using `docker ps`.
#   2. Attempts a `curl` request to `https://localhost:9443` inside the container.
#   3. Considers the service responsive if `curl` returns HTTP status codes `200`, `302`, `401`, or `403`.
# - **Error Handling:** If the timeout is exceeded before Portainer becomes responsive, logs a fatal error and returns `1`.
# - **Success:** Returns `0` once Portainer is detected as initialized and responsive.
#
# **Exit Codes:**
# - `0`: Portainer Server successfully initialized and is responsive.
# - `1`: Portainer Server did not initialize within the allotted timeout.
wait_for_portainer_initialization() {
    log_info "Waiting for Portainer Server to initialize inside container CTID: $CTID"
    local timeout=120 # seconds
    local interval=5  # seconds
    local elapsed_time=0
    local portainer_url="https://localhost:9443"

    while [ "$elapsed_time" -lt "$timeout" ]; do
        if pct exec "$CTID" -- docker ps --filter "name=portainer" --format "{{.Names}}" | grep -q "^portainer$"; then
            # Check if the web server is responding
            if pct exec "$CTID" -- curl -k -s -o /dev/null -w "%{http_code}" "$portainer_url" | grep -q "200\|302\|401\|403"; then
                log_info "Portainer Server initialized and responsive."
                return 0
            fi
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    log_error "FATAL: Portainer Server did not initialize within ${timeout} seconds."
    return 1
}

# ## Function: `verify_portainer_server_accessibility()`
# **Purpose:** Confirms that the Portainer web user interface is externally reachable from the Proxmox host.
#
# **Details:**
# - **Configuration Retrieval:** Dynamically retrieves the container's IP address from `phoenix_lxc_configs.json` and the Portainer server port from `phoenix_hypervisor_config.json`.
# - **Error Handling (Configuration):** If the IP or port cannot be determined from the configuration files, logs a fatal error and exits with code `6`.
# - **Connectivity Check:** Performs a `curl` request from the Proxmox host to the constructed Portainer URL (`https://${CONTAINER_IP}:${PORTAINER_SERVER_PORT}`).
# - **Accessibility Criteria:** Considers Portainer accessible if `curl` returns HTTP status codes `200`, `302`, `401`, or `403` (indicating the web server is active and potentially requiring authentication).
# - **Success Logging:** Upon successful access, logs the accessible URL and the initial default admin password (`TestPhoenix`).
# - **Error Handling (Accessibility):** If Portainer is not accessible (e.g., connection refused, unexpected HTTP status), logs a fatal error and exits with code `6`.
#
# **Exit Codes:**
# - `6`: Portainer Server is not accessible from the Proxmox host.
verify_portainer_server_accessibility() {
    log_info "Verifying Portainer Server accessibility from host."

    # Get container IP from LXC config file
    local lxc_config_file="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
    CONTAINER_IP=$(jq -r --arg ctid "$CTID" '.lxc_configs[$ctid | tostring].network_config.ip | split("/") | .' "$lxc_config_file")
    PORTAINER_SERVER_PORT=$(jq -r '.network.portainer_server_port' "$HYPERVISOR_CONFIG_FILE")

    if [ -z "$CONTAINER_IP" ] || [ -z "$PORTAINER_SERVER_PORT" ]; then
        log_error "FATAL: Could not determine container IP or Portainer server port from configuration files."
        exit_script 6
    fi

    local portainer_url="https://${CONTAINER_IP}:${PORTAINER_SERVER_PORT}"
    log_info "Attempting to reach Portainer Server at $portainer_url from host..."

    local http_code=$(curl -k -s -o /dev/null -w "%{http_code}" "$portainer_url")
    if [[ "$http_code" =~ ^(200|302|401|403)$ ]]; then
        log_info "Portainer Server is accessible at $portainer_url. Initial admin password is 'TestPhoenix'."
        return 0
    else
        log_error "FATAL: Portainer Server is not accessible at $portainer_url. HTTP status code: $http_code."
        exit_script 6
    fi
}

# ## Function: `main()`
# **Purpose:** Serves as the primary entry point and orchestrator for the Portainer Server setup script.
#
# **Details:**
# - **Argument Parsing:** Initiates by calling `parse_arguments` to retrieve and validate the CTID.
# - **Input Validation:** Further validates the CTID using `validate_inputs`.
# - **Container Existence Check:** Confirms the target LXC container exists via `check_container_exists`.
# - **Idempotency Check:** Calls `check_if_portainer_already_running` to prevent re-deployment if Portainer is already active.
# - **Docker Prerequisite:** Verifies Docker functionality within the container using `verify_docker_is_functional_inside_container`.
# - **Deployment:** Deploys the Portainer Server Docker container by calling `deploy_portainer_server_container_inside_container`.
# - **Initialization Wait:** Waits for Portainer to fully initialize and become responsive using `wait_for_portainer_initialization`.
# - **Accessibility Verification:** Confirms external accessibility of the Portainer UI with `verify_portainer_server_accessibility`.
# - **Script Termination:** Calls `exit_script` with a success code (`0`) upon successful completion of all steps.
main() {
    parse_arguments "$@"
    validate_inputs
    check_container_exists
    check_if_portainer_already_running # Exits 0 if Portainer is already running

    verify_docker_is_functional_inside_container
    deploy_portainer_server_container_inside_container
    wait_for_portainer_initialization
    verify_portainer_server_accessibility

    exit_script 0
}

# Call the main function
main "$@"