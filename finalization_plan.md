# Finalization Plan: Bringing the Phoenix Infrastructure Online

This document outlines the final, sequential steps required to validate the existing infrastructure, provision the remaining components, and bring the entire system into a fully operational and synchronized state.

## Phase 1: Validate VM 1001 (Portainer)

The first step is to formally verify the health of the already-provisioned Portainer VM.

1.  **Execute Health Check**: Run the foundational health check script against VM 1001. This will provide a high degree of confidence that its core integrations with the infrastructure are sound.
    *   **Command**: `phoenix health-check 1001`
    *   **Expected Outcome**: The script should pass all five phases:
        1.  Prerequisites (all core LXCs and the VM are running).
        2.  DNS Resolution (internal hostname resolves correctly).
        3.  Firewall (firewall is active on the network interface).
        4.  Certificate Trust (the internal root CA is trusted).
        5.  Docker Service (the Docker daemon is responsive).

## Phase 2: Create VM 1002 (drphoenix)

With VM 1001 validated, we can proceed to create the second VM, which will host the Portainer agent and application stacks.

1.  **Execute Create Command**: Run the `create` command for VM 1002. The `phoenix-cli` orchestrator will automatically handle the dependency on VM 1001.
    *   **Command**: `phoenix create 1002`
    *   **Expected Execution Flow**:
        *   The `vm-manager.sh` will be invoked for VMID `1002`.
        *   It will clone the base template (VM 9000).
        *   It will apply all foundational configurations (network, resources, NFS volumes).
        *   It will execute the feature scripts: `base_setup`, `trusted_ca`, `step_cli`, and `docker`.
        *   As part of its provisioning, it will deploy the Portainer **agent** container inside the VM.
    *   **Docker & Step CA Integration**: The `trusted_ca` feature runs before the `docker` feature. This ensures that the Docker daemon is installed on a system that already trusts the internal "Phoenix Root CA". As a result, Docker will be ready to securely communicate with any internal services (like a future private registry) that use certificates issued by your Step CA.

## Phase 3: Synchronize the Entire System

This is the final and most critical step. The `sync all` command is the master orchestrator that ties all components together, from the service mesh to the application layer.

1.  **Execute Sync Command**:
    *   **Command**: `phoenix sync all`
    *   **Expected Execution Flow (handled by `portainer-manager.sh`)**:
        1.  **System Health Check**: The script begins by running a comprehensive suite of health checks to ensure the core infrastructure (DNS, Nginx, Traefik, Step-CA) is stable and ready.
        2.  **Portainer Authentication**: It connects to the Portainer API (via the Nginx gateway) and acquires an authentication token. It will also create the admin user if it doesn't exist.
        3.  **Endpoint Registration**: The script discovers the Portainer agent running on VM 1002 (via its internal DNS name) and registers it as a new "environment" (endpoint) in the Portainer server.
        4.  **Stack Deployment**: It reads the `docker_stacks` definitions from `phoenix_vm_configs.json` and `phoenix_stacks_config.json`. For each defined stack (e.g., `qdrant_service`, `thinkheads_ai_app`), it uses the Portainer API to deploy the corresponding Docker Compose file to the correct environment (VM 1002).
        5.  **Service Mesh & Gateway Sync**: Finally, it regenerates the Traefik and Nginx configurations to include the newly deployed services and reloads them. This makes the applications securely accessible from both inside and outside the cluster.

This phased approach ensures that each component is validated before we proceed to the next, culminating in a fully synchronized and operational environment.