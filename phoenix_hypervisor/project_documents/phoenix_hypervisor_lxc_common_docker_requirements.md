# `phoenix_hypervisor_lxc_common_docker.sh` - Requirements

## Overview

This document outlines the detailed requirements for the `phoenix_hypervisor_lxc_common_docker.sh` script. This script installs and configures Docker Engine inside a specific LXC container and integrates it with Portainer.

## Key Aspects & Responsibilities

*   **Role:** Install and configure Docker Engine and Portainer components inside an LXC container.
*   **Input:**
    *   `CTID` (Container ID) as a mandatory command-line argument.
    *   Environment variables set by the orchestrator: `PORTAINER_ROLE`, `PORTAINER_SERVER_IP`, `PORTAINER_AGENT_PORT`.
*   **Process:**
    *   Uses `pct exec` to run commands inside the container to install Docker, NVIDIA Container Toolkit, configure the daemon for NVIDIA runtime, manage user groups, start the service, and run Portainer containers.
*   **Execution Context:** Runs non-interactively on the Proxmox host. Uses `pct` and file system commands.
*   **Idempotency:** Checks if Docker/Portainer components are already installed/configured inside the container and skips actions if they are.
*   **Error Handling:** Provides detailed logs for all actions and failures. Exits with a standard code: 0 for success, non-zero for failure.
*   **Output:** Detailed logs indicating the steps taken and the outcome of the configuration process.

## Function Sequence, Content, and Purpose

### `main()`
*   **Content:**
    *   Entry point.
    *   Calls `parse_arguments` to get the CTID.
    *   Calls `validate_inputs` (CTID, required environment variables).
    *   Calls `check_container_exists` (basic sanity check).
    *   Calls `install_and_configure_docker_in_container`.
    *   Calls `exit_script`.
*   **Purpose:** Controls the overall flow of the Docker configuration process.

### `parse_arguments()`
*   **Content:**
    *   Checks the number of command-line arguments.
    *   If not exactly one argument is provided, logs a usage error message and calls `exit_script 2`.
    *   Assigns the first argument to a variable `CTID`.
    *   Logs the received CTID.
*   **Purpose:** Retrieves the CTID from the command-line arguments.

### `validate_inputs()`
*   **Content:**
    *   Validates that `CTID` is a positive integer. If not, logs a fatal error and calls `exit_script 2`.
    *   Checks if the required environment variables are set and not empty: `PORTAINER_ROLE`. If missing/empty, logs a fatal error and calls `exit_script 2`.
    *   Checks if `PORTAINER_ROLE` is one of "server", "agent", or "none". If not, logs a fatal error and calls `exit_script 2`.
    *   If `PORTAINER_ROLE` is "agent", checks if `PORTAINER_SERVER_IP` and `PORTAINER_AGENT_PORT` are set and not empty. If missing/empty, logs a fatal error and calls `exit_script 2`.
    *   Logs the values of the validated environment variables.
*   **Purpose:** Ensures the script has the necessary and valid inputs (CTID, environment variables) to proceed.

### `check_container_exists()`
*   **Content:**
    *   Logs checking for the existence of container `CTID`.
    *   Executes `pct status "$CTID" > /dev/null 2>&1`.
    *   Captures the exit code.
    *   If the exit code is non-zero (container does not exist or error), logs a fatal error and calls `exit_script 3`.
    *   If the exit code is 0 (container exists), logs confirmation.
*   **Purpose:** Performs a basic sanity check that the target container exists.

### `wait_for_portainer_ready()`
*   **Content:**
    *   Polls a given Portainer URL inside the container until it returns a healthy status (200, 302, 401, or 403) or a timeout is reached.
    *   Arguments: `CTID`, `container_name`, `portainer_url`.
    *   Logs appropriate messages for success, polling, and timeout.
*   **Purpose:** Provides a robust readiness check for Portainer containers.

### `install_and_configure_docker_in_container()`
*   **Content:**
    *   Logs starting Docker software installation and configuration inside container `CTID`.
    *   Defines constants/paths:
        *   `DEFAULT_USER="ubuntu"` (Standard user for Ubuntu template).
        *   `DOCKER_DAEMON_CONFIG_FILE="/etc/docker/daemon.json"` (Path inside the container).
        *   `NVIDIA_RUNTIME_CONFIG` (JSON snippet for NVIDIA runtime).
        *   `PORTAINER_SERVER_IMAGE` (Dynamically loaded from `phoenix_hypervisor_config.json`).
        *   `PORTAINER_AGENT_IMAGE` (Dynamically loaded from `phoenix_hypervisor_config.json`).
    *   **Idempotency Check:**
        *   Logs performing idempotency check.
        *   Checks if `docker` command exists inside the container (`pct exec "$CTID" -- command -v docker > /dev/null 2>&1`).
        *   Checks if `dockerd` service is active inside the container (`pct exec "$CTID" -- systemctl is-active docker > /dev/null 2>&1`).
        *   Checks if `DEFAULT_USER` is in the `docker` group (`pct exec "$CTID" -- groups "$DEFAULT_USER" | grep -q docker`).
        *   Checks if the NVIDIA Container Toolkit is installed (`pct exec "$CTID" -- dpkg -l | grep -q nvidia-container-toolkit`).
        *   Checks if the required Portainer container (based on `PORTAINER_ROLE`) is running (`pct exec "$CTID" -- docker ps --filter "name=^portainer$"` or `^portainer_agent$`).
        *   If all relevant checks pass:
            *   Logs that Docker/Portainer appears to be correctly installed and configured.
            *   Skips remaining installation steps.
            *   Returns.
        *   If any check fails, logs that installation/configuration is needed.
    *   **Add Docker Repository:**
        *   Logs adding Docker official repository inside the container.
        *   Executes `pct exec "$CTID" -- apt-get update`.
        *   Executes `pct exec "$CTID" -- apt-get install -y ca-certificates curl gnupg lsb-release`.
        *   Executes `pct exec "$CTID" -- mkdir -p /etc/apt/keyrings`.
        *   Executes `pct exec "$CTID" -- curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg`.
        *   Executes `pct exec "$CTID" -- chmod a+r /etc/apt/keyrings/docker.gpg`.
        *   Executes `pct exec "$CTID" -- echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null`.
        *   Executes `pct exec "$CTID" -- apt-get update`.
        *   Handles errors at each step.
    *   **Install Docker Engine & Compose Plugin:**
        *   Logs installing Docker Engine and Compose Plugin.
        *   Executes `pct exec "$CTID" -- apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin`.
        *   Handles errors.
    *   **Install NVIDIA Container Toolkit:**
        *   Logs installing NVIDIA Container Toolkit.
        *   Executes `pct exec "$CTID" -- apt-get install -y nvidia-container-toolkit`.
        *   Handles errors (e.g., package not found if NVIDIA repo not configured).
    *   **Configure Docker Daemon for NVIDIA Runtime:**
        *   Logs configuring Docker daemon for NVIDIA runtime.
        *   Defines the NVIDIA runtime configuration JSON string.
        *   Executes `pct exec "$CTID" -- mkdir -p "$(dirname "$DOCKER_DAEMON_CONFIG_FILE")"`.
        *   Executes `pct exec "$CTID" -- echo '<NVIDIA_RUNTIME_CONFIG_JSON>' > "$DOCKER_DAEMON_CONFIG_FILE"`. (Replace `<NVIDIA_RUNTIME_CONFIG_JSON>` with the actual JSON string).
        *   Handles errors.
    *   **User Group Management:**
        *   Logs adding user "$DEFAULT_USER" to the docker group.
        *   Executes `pct exec "$CTID" -- usermod -aG docker "$DEFAULT_USER"`.
        *   Handles errors.
    *   **Start Docker Service:**
        *   Logs starting and enabling Docker service.
        *   Executes `pct exec "$CTID" -- systemctl enable docker --now`.
        *   Handles errors.
        *   Verifies service is active (`pct exec "$CTID" -- systemctl is-active docker`).
    *   **Portainer Integration:**
        *   Based on `PORTAINER_ROLE`:
            *   **If "server":**
                *   Logs setting up Portainer Server.
                *   Executes `pct exec "$CTID" -- docker volume create portainer_data`.
                *   Handles errors.
                *   Executes `pct exec "$CTID" -- docker run -d -p 9443:9443 -p 9001:9001 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data "$PORTAINER_SERVER_IMAGE"`.
                *   Handles errors.
                *   Calls `wait_for_portainer_ready` for Portainer Server (e.g., `https://localhost:9443`).
            *   **If "agent":**
                *   Logs setting up Portainer Agent.
                *   Constructs `AGENT_CLUSTER_ADDR="tcp://${PORTAINER_SERVER_IP}:${PORTAINER_AGENT_PORT}"`.
                *   Executes `pct exec "$CTID" -- docker volume create portainer_agent_data`.
                *   Handles errors.
                *   Executes `pct exec "$CTID" -- docker run -d --name portainer_agent --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker/volumes:/var/lib/docker/volumes -v portainer_agent_data:/data -e AGENT_CLUSTER_ADDR="$AGENT_CLUSTER_ADDR" "$PORTAINER_AGENT_IMAGE"`.
                *   Handles errors.
                *   Calls `wait_for_portainer_ready` for Portainer Agent (e.g., `http://localhost:9999/status`).
            *   **If "none":**
                *   Logs that Portainer role is 'none', skipping Portainer container setup.
    *   **Final Verification (inside Container):**
        *   Logs performing final verification of Docker installation.
        *   Executes `pct exec "$CTID" -- docker info`.
        *   Captures and logs relevant parts of the output (e.g., Docker version, running status, if NVIDIA runtime is listed).
        *   Handles errors.
    *   Logs completion of Docker software installation and configuration.
*   **Purpose:** Installs Docker Engine, NVIDIA Container Toolkit, configures the daemon, manages user groups, starts the service, and sets up Portainer inside the LXC container using `pct exec`.

### `exit_script(exit_code)`
*   **Content:**
    *   Accepts an integer `exit_code`.
    *   If `exit_code` is 0:
        *   Logs a success message (e.g., "Script completed successfully.").
    *   If `exit_code` is non-zero:
        *   Logs a failure message (e.g., "Script failed with exit code <exit_code>.").
    *   Ensures logs are flushed.
    *   Exits the script with the provided `exit_code`.
*   **Purpose:** Provides a single point for script termination, ensuring final logging and correct exit status based on the overall outcome.

## Exit Codes
*   **0:** Success
*   **1:** General error
*   **2:** Invalid input/arguments
*   **3:** Container does not exist
*   **4:** Docker installation/configuration error
*   **5:** Portainer setup error