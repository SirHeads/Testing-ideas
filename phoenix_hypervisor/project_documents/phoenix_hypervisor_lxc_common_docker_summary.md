# `phoenix_hypervisor_lxc_docker.sh` - Summary

## Overview

This document summarizes the purpose, responsibilities, and key interactions of the `phoenix_hypervisor_lxc_docker.sh` script within the Phoenix Hypervisor system.

## Purpose

The `phoenix_hypervisor_lxc_docker.sh` script is responsible for installing and configuring Docker Engine *inside* a specific LXC container. This enables the container to run its own set of isolated applications and services using Docker. The script also handles the integration of the container with the Portainer management system and ensures GPU access for Docker containers if the parent LXC has GPU access.

## Key Responsibilities

1.  **Conditional Execution:**
    *   Designed to be called by `phoenix_establish_hypervisor.sh` only for containers where `config_block.features` contains `nesting=1`, indicating Docker-in-LXC capability.

2.  **Docker Engine Installation (Container):**
    *   Receive the `CTID` and `portainer_role` from the orchestrator.
    *   Use `pct exec` (or similar) to run commands inside the specified LXC container.
    *   Add the official Docker APT repository inside the container.
    *   Install the Docker Engine packages (`docker-ce`, `docker-ce-cli`, `containerd.io`) via `apt`.
    *   Install `docker-compose-plugin` for Docker Compose v2 support.

3.  **NVIDIA Container Toolkit Integration (Container):**
    *   Install the `nvidia-container-toolkit` package inside the container using `apt`.
    *   This relies on the assumption that the NVIDIA repository (`nvidia_repo_url`) has been added by the preceding `phoenix_hypervisor_lxc_nvidia.sh` script.
    *   This enables Docker containers *within* this LXC to access the GPUs passed through to the LXC.

4.  **User Configuration (Container):**
    *   Add the default container user (e.g., `ubuntu` for Ubuntu templates) to the `docker` group, granting it permission to run Docker commands without `sudo`.

5.  **Docker Service Management (Container):**
    *   Enable and start the Docker service (`dockerd`) inside the container using `systemctl`.
    *   Verify that the Docker service is active and running.

6.  **Portainer Integration (Container):**
    *   Based on the `portainer_role` received from the orchestrator:
        *   **If "server":**
            *   Pull the official Portainer Server Docker image.
            *   Run the Portainer Server container, mapping the necessary ports (e.g., 9443 for UI, 9001 for edge agents) and mounting the Docker socket (`/var/run/docker.sock`) for management.
        *   **If "agent":**
            *   Pull the official Portainer Agent Docker image.
            *   Run the Portainer Agent container, connecting it to the Portainer Server using the provided `PORTAINER_SERVER_IP` (passed by the orchestrator), and mounting the Docker socket (`/var/run/docker.sock`).
        *   **If "none":**
            *   No specific Portainer container is started, although the Docker environment is prepared.

7.  **Execution Context:**
    *   Runs non-interactively on the Proxmox host.
    *   Uses `pct exec` (or potentially SSH) to execute commands inside the target LXC container.

8.  **Idempotency:**
    *   Designed to be safe to run multiple times. Checks for the existence of Docker, the Docker service status, and the presence of Portainer containers before attempting installation/configuration steps.

9.  **Logging & Error Handling:**
    *   Provide detailed logs of the process, including commands run inside the container and verification outputs.
    *   Report success or failure back to the calling orchestrator (`phoenix_establish_hypervisor.sh`) via a standard exit code (0 for success, non-zero for failure).

## Interaction with Other Components

*   **Called By:** `phoenix_establish_hypervisor.sh` for containers configured for Docker (`features` includes `nesting=1`).
*   **Input:** `CTID`, `portainer_role`. Environment variables like `PORTAINER_SERVER_IP` passed by the orchestrator.
*   **Configuration Source:** Relies on information passed from the orchestrator, which originates from `phoenix_lxc_configs.json` (for `portainer_role`) and `phoenix_hypervisor_config.json` (for `PORTAINER_SERVER_IP`).
*   **Reports To:** `phoenix_establish_hypervisor.sh` via exit code and logs.
*   **Precedes:** Potentially `phoenix_hypervisor_setup_<CTID>.sh`, which are called by the orchestrator after this script completes successfully.
*   **Assumes:** That `phoenix_hypervisor_lxc_nvidia.sh` has already run successfully if GPU access is required, ensuring the NVIDIA drivers and repositories are set up inside the container.

## Output & Error Handling

*   **Output:** Detailed logs indicating the steps taken inside the container (repository added, packages installed, service started, Portainer container run), including checks for service status.
*   **Error Handling:** Standard exit codes (0 for success, non-zero for failure) to communicate status to the orchestrator. Detailed logging provides context for any failures, such as `pct exec` failures, package installation errors, or service start failures.