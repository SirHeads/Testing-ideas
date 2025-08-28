# `phoenix_hypervisor_lxc_docker.sh` - Detailed Requirements

## Overview

This document outlines the detailed requirements for the `phoenix_hypervisor_lxc_docker.sh` script. This script installs and configures Docker Engine inside a specific LXC container and integrates it with Portainer.

## 1. Key Aspects & Responsibilities

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

## 2. Function Sequence, Content, and Purpose

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
    *   Check the number of command-line arguments.
    *   If not exactly one argument is provided, log a usage error message and call `exit_script 1`.
    *   Assign the first argument to a variable `CTID`.
    *   Log the received CTID.
*   **Purpose:** Retrieves the CTID from the command-line arguments.

### `validate_inputs()`
*   **Content:**
    *   Validate that `CTID` is a positive integer. If not, log a fatal error and call `exit_script 1`.
    *   Check if the required environment variables are set and not empty: `PORTAINER_ROLE`. If missing/empty, log a fatal error and call `exit_script 1`.
    *   Check if `PORTAINER_ROLE` is one of "server", "agent", or "none". If not, log a fatal error and call `exit_script 1`.
    *   If `PORTAINER_ROLE` is "agent", check if `PORTAINER_SERVER_IP` and `PORTAINER_AGENT_PORT` are set and not empty. If missing/empty, log a fatal error and call `exit_script 1`.
    *   Log the values of the validated environment variables.
*   **Purpose:** Ensures the script has the necessary and valid inputs (CTID, environment variables) to proceed.

### `check_container_exists()`
*   **Content:**
    *   Log checking for the existence of container `CTID`.
    *   Execute `pct status "$CTID" > /dev/null 2>&1`.
    *   Capture the exit code.
    *   If the exit code is non-zero (container does not exist or error), log a fatal error and call `exit_script 1`.
    *   If the exit code is 0 (container exists), log confirmation.
*   **Purpose:** Performs a basic sanity check that the target container exists.

### `install_and_configure_docker_in_container()`
*   **Content:**
    *   Log starting Docker software installation and configuration inside container `CTID`.
    *   Define constants/paths:
        *   `DEFAULT_USER="ubuntu"` (Standard user for Ubuntu template).
        *   `DOCKER_DAEMON_CONFIG_FILE="/etc/docker/daemon.json"` (Path inside the container).
        *   `NVIDIA_RUNTIME_CONFIG` (JSON snippet for NVIDIA runtime).
        *   `PORTAINER_SERVER_IMAGE="portainer/portainer-ce:2.33.1-lts"` (Explicit LTS version).
        *   `PORTAINER_AGENT_IMAGE="portainer/agent:2.33.1-lts"` (Explicit LTS version).
    *   **Idempotency Check:**
        *   Log performing idempotency check.
        *   Check if `docker` command exists inside the container (`pct exec "$CTID" -- command -v docker > /dev/null 2>&1`).
        *   Check if `dockerd` service is active inside the container (`pct exec "$CTID" -- systemctl is-active docker > /dev/null 2>&1`).
        *   Check if `DEFAULT_USER` is in the `docker` group (`pct exec "$CTID" -- groups "$DEFAULT_USER" | grep -q docker`).
        *   Check if the NVIDIA Container Toolkit is installed (`pct exec "$CTID" -- dpkg -l | grep -q nvidia-container-toolkit`).
        *   Check if the required Portainer container (based on `PORTAINER_ROLE`) is running (`pct exec "$CTID" -- docker ps --filter "name=portainer*" --format "{{.Names}}" | grep -q "^portainer$"` or `^portainer_agent$`).
        *   If all relevant checks pass:
            *   Log that Docker/Portainer appears to be correctly installed and configured.
            *   Skip remaining installation steps.
            *   Return.
        *   If any check fails, log that installation/configuration is needed.
    *   **Add Docker Repository:**
        *   Log adding Docker official repository inside the container.
        *   Execute `pct exec "$CTID" -- apt-get update`.
        *   Execute `pct exec "$CTID" -- apt-get install -y ca-certificates curl gnupg lsb-release`.
        *   Execute `pct exec "$CTID" -- mkdir -p /etc/apt/keyrings`.
        *   Execute `pct exec "$CTID" -- curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg`.
        *   Execute `pct exec "$CTID" -- chmod a+r /etc/apt/keyrings/docker.gpg`.
        *   Execute `pct exec "$CTID" -- echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null`.
        *   Execute `pct exec "$CTID" -- apt-get update`.
        *   Handle errors at each step.
    *   **Install Docker Engine & Compose Plugin:**
        *   Log installing Docker Engine and Compose Plugin.
        *   Execute `pct exec "$CTID" -- apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin`.
        *   Handle errors.
    *   **Install NVIDIA Container Toolkit:**
        *   Log installing NVIDIA Container Toolkit.
        *   Execute `pct exec "$CTID" -- apt-get install -y nvidia-container-toolkit`.
        *   Handle errors (e.g., package not found if NVIDIA repo not configured).
    *   **Configure Docker Daemon for NVIDIA Runtime:**
        *   Log configuring Docker daemon for NVIDIA runtime.
        *   Define the NVIDIA runtime configuration JSON string.
        *   Execute `pct exec "$CTID" -- mkdir -p "$(dirname "$DOCKER_DAEMON_CONFIG_FILE")"`.
        *   Execute `pct exec "$CTID" -- echo '<NVIDIA_RUNTIME_CONFIG_JSON>' > "$DOCKER_DAEMON_CONFIG_FILE"`. (Replace `<NVIDIA_RUNTIME_CONFIG_JSON>` with the actual JSON string).
        *   Handle errors.
    *   **User Group Management:**
        *   Log adding user "$DEFAULT_USER" to the docker group.
        *   Execute `pct exec "$CTID" -- usermod -aG docker "$DEFAULT_USER"`.
        *   Handle errors.
    *   **Start Docker Service:**
        *   Log starting and enabling Docker service.
        *   Execute `pct exec "$CTID" -- systemctl enable docker --now`.
        *   Handle errors.
        *   Verify service is active (`pct exec "$CTID" -- systemctl is-active docker`).
    *   **Portainer Integration:**
        *   Based on `PORTAINER_ROLE`:
            *   **If "server":**
                *   Log setting up Portainer Server.
                *   Execute `pct exec "$CTID" -- docker volume create portainer_data`.
                *   Handle errors.
                *   Execute `pct exec "$CTID" -- docker run -d -p 9443:9443 -p 9001:9001 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data "$PORTAINER_SERVER_IMAGE"`.
                *   Handle errors.
                *   Log sleeping 5 seconds for Portainer Server to initialize.
                *   Execute `sleep 5`.
                *   Check if the container started (`pct exec "$CTID" -- docker ps --filter "name=^portainer$" --format "{{.Names}}" | grep -q "^portainer$"`). Log result.
            *   **If "agent":**
                *   Log setting up Portainer Agent.
                *   Construct `AGENT_CLUSTER_ADDR="tcp://${PORTAINER_SERVER_IP}:${PORTAINER_AGENT_PORT}"`.
                *   Execute `pct exec "$CTID" -- docker volume create portainer_agent_data`.
                *   Handle errors.
                *   Execute `pct exec "$CTID" -- docker run -d --name portainer_agent --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker/volumes:/var/lib/docker/volumes -v portainer_agent_data:/data -e AGENT_CLUSTER_ADDR="$AGENT_CLUSTER_ADDR" "$PORTAINER_AGENT_IMAGE"`.
                *   Handle errors.
                *   Log sleeping 5 seconds for Portainer Agent to initialize.
                *   Execute `sleep 5`.
                *   Check if the container started (`pct exec "$CTID" -- docker ps --filter "name=^portainer_agent$" --format "{{.Names}}" | grep -q "^portainer_agent$"`). Log result.
            *   **If "none":**
                *   Log that Portainer role is 'none', skipping Portainer container setup.
    *   **Final Verification (inside Container):**
        *   Log performing final verification of Docker installation.
        *   Execute `pct exec "$CTID" -- docker info`.
        *   Capture and log relevant parts of the output (e.g., Docker version, running status, if NVIDIA runtime is listed).
        *   Handle errors.
    *   Log completion of Docker software installation and configuration.
*   **Purpose:** Installs Docker Engine, NVIDIA Container Toolkit, configures the daemon, manages user groups, starts the service, and sets up Portainer inside the LXC container using `pct exec`.

### `exit_script(exit_code)`
*   **Content:**
    *   Accept an integer `exit_code`.
    *   If `exit_code` is 0:
        *   Log a success message (e.g., "Docker configuration for container CTID completed successfully").
    *   If `exit_code` is non-zero:
        *   Log a failure message indicating the script encountered an error.
    *   Ensure logs are flushed.
    *   Exit the script with the provided `exit_code`.
*   **Purpose:** Provides a single point for script termination, ensuring final logging and correct exit status based on the overall outcome.