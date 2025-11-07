# Test Plan: Portainer Community Edition Integration

**Objective:** To validate that the `phoenix-cli` can successfully deploy and manage Docker stacks using Portainer Community Edition after modifying the endpoint creation and agent deployment logic.

### Pre-requisites:

1.  A clean environment. All existing Portainer containers (server and agents) should be stopped and removed.
2.  The `phoenix_hypervisor_config.json` is correctly configured with all necessary VM and network details.

### Test Execution Steps:

1.  **Environment Teardown (Manual):**
    *   SSH into the Portainer server VM (VMID 1001).
    *   Run `docker compose down -v` in the Portainer deployment directory to stop and remove the Portainer server and its associated volumes.
    *   SSH into all Portainer agent VMs.
    *   Run `docker rm -f portainer_agent` to stop and remove the agent containers.

2.  **Execute Full System Sync:**
    *   From the hypervisor, run the command:
        ```bash
        /usr/local/phoenix_hypervisor/bin/phoenix-cli sync all --reset-portainer
        ```
    *   The `--reset-portainer` flag will ensure a clean deployment.
    *   Monitor the output for any errors. The script should complete successfully.

3.  **Verification Steps:**

    *   **Step 3.1: Verify Portainer Server:**
        *   Access the Portainer UI via its FQDN (e.g., `https://portainer.internal.thinkheads.ai`).
        *   Log in with the admin credentials defined in the configuration.
        *   The UI should be accessible and fully functional.

    *   **Step 3.2: Verify Portainer Endpoints:**
        *   In the Portainer UI, navigate to the "Environments" (or "Endpoints") section.
        *   Verify that an environment exists for each VM defined as a Portainer agent in the configuration.
        *   Click on each environment. The status should be "up" and green.
        *   The URL for each endpoint should be a `tcp://` address (e.g., `tcp://10.0.0.112:9001`), not `https://`.

    *   **Step 3.3: Verify Portainer Agent Containers:**
        *   SSH into one of the Portainer agent VMs.
        *   Run `docker ps` and confirm that the `portainer_agent` container is running.
        *   Run `docker logs portainer_agent`. The logs should not indicate any TLS or certificate errors.

    *   **Step 3.4: Verify Stack Deployment:**
        *   The `sync all` command should have deployed the stacks defined in your `phoenix_stacks_config.json`.
        *   In the Portainer UI, navigate to the "Stacks" section.
        *   Verify that all expected stacks are listed and running.
        *   Click on a stack and check the container status to ensure all services are "running".

    *   **Step 3.5: Verify Application Accessibility:**
        *   Identify a service that should be exposed via the Traefik gateway.
        *   Attempt to access the service's FQDN from a machine on the network.
        *   The application should load and function as expected.

### Expected Outcome:

The `phoenix sync all` command completes without error. The Portainer server and agents are deployed, endpoints are created as standard TCP connections, and all Docker stacks are successfully deployed and accessible. The system is fully functional, demonstrating a successful integration with Portainer Community Edition.