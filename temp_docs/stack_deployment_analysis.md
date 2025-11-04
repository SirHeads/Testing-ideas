# Docker Stack Deployment Analysis

This document analyzes the process by which the `portainer-manager.sh` script deploys Docker stacks to the `drphoenix` VM (VM 1002) via the Portainer API.

## Process Overview

The `sync_stack` function in `portainer-manager.sh` is the core of the stack deployment process. It is a file-based deployment method that leverages the shared NFS volume between the hypervisor and the VMs.

1.  **Stack Discovery:** The `sync_all` function first calls `discover_stacks` to find all available stacks in the `/usr/local/phoenix_hypervisor/stacks` directory.
2.  **File Preparation:** For each stack to be deployed, the `sync_stack` function:
    *   Copies the `docker-compose.yml` file from the stack's directory on the hypervisor to a corresponding directory on the shared NFS volume (e.g., `/mnt/pve/quickOS/vm-persistent-data/1002/stacks/<stack_name>/`).
    *   Injects any Traefik labels defined in the stack's `phoenix.json` manifest directly into the `docker-compose.yml` file on the NFS share.
3.  **API Call:** The script then makes a POST or PUT request to the Portainer API's `/api/stacks` endpoint.
    *   **Payload:** The JSON payload of this request does **not** contain the content of the compose file. Instead, it contains the path to the `docker-compose.yml` file as it is seen from within the Portainer agent container (e.g., `/persistent-storage/stacks/<stack_name>/docker-compose.yml`).
    *   **Idempotency:** The script first checks if a stack with the same name already exists. If it does, it makes a PUT request to update the stack. If not, it makes a POST request to create it.
4.  **Deployment:** Upon receiving the API request, the Portainer server instructs the agent on VM 1002 to execute a `docker compose up` command, using the compose file from the specified path on the NFS share.

## Key Components

-   **NFS Share:** The shared NFS volume is the backbone of this deployment method. It allows the hypervisor to prepare the compose files and the Portainer agent to access them.
-   **`phoenix.json` Manifest:** This file within each stack's directory provides the metadata for the deployment, including Traefik labels and environment variables.
-   **Portainer API:** The API is used to orchestrate the deployment, but the actual deployment logic is handled by the Portainer agent and Docker Compose.

## Potential Issues

1.  **NFS Permissions:** If the file permissions on the NFS share are incorrect, the Portainer agent (running as the `root` user inside its container) may not be able to read the `docker-compose.yml` file. This is a very common source of "file not found" errors during stack deployment.
2.  **Path Mismatches:** The path to the compose file in the Portainer API call must be the exact path as seen from *inside* the Portainer agent container. Any discrepancy between the hypervisor's view of the NFS share and the agent's view will cause the deployment to fail.
3.  **Compose File Errors:** A syntax error in the `docker-compose.yml` file or the dynamically injected Traefik labels will cause the `docker compose up` command to fail.
4.  **Image Pull Failures:** The `drphoenix` VM must have a working internet connection and be able to resolve the DNS names of the Docker registries to pull the required images. Firewall rules or DNS issues can prevent this.
5.  **External Volume Failures:** The `portainer_service/docker-compose.yml` defines an external volume `portainer_data_nfs`. If this volume is not created before the stack is deployed, the deployment will fail. The `deploy_portainer_instances` function in `portainer-manager.sh` is responsible for creating this volume.
