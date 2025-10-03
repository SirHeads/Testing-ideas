# Portainer Implementation Plan

**Version:** 1.0
**Date:** 2025-10-03
**Author:** Roo
**Status:** Approved

## 1. Executive Summary

This document outlines the detailed implementation plan for deploying Portainer within the Phoenix Hypervisor environment. The plan is designed to be consistent with the existing infrastructure-as-code principles of the project, leveraging declarative configurations and automated scripting to ensure a repeatable and maintainable deployment.

The core of this plan is to deploy Portainer as a Docker container within VM 1001, with persistent data stored on a dedicated NFS volume. The service will be securely exposed through the existing Nginx gateway in LXC 101.

## 2. Implementation Phases

The implementation will be carried out in the following phases:

### Phase 1: Declarative Configuration

This phase focuses on updating the core JSON configuration files to define the desired state of the system.

*   **Task 1.1: Configure Persistent Storage for VM 1001**
    *   **File:** `usr/local/phoenix_hypervisor/etc/phoenix_vm_configs.json`
    *   **Action:** Correct the `path` for the NFS volume associated with VM 1001 to ensure it points to the correct directory on the hypervisor.
    *   **Change:**
        ```json
        "path": "/quickOS/vm-persistent-data/1001"
        ```

*   **Task 1.2: Update Nginx Gateway Configuration**
    *   **File:** `usr/local/phoenix_hypervisor/etc/nginx/sites-available/vllm_gateway`
    *   **Action:** Update the `portainer_service` upstream definition to point to the IP address of VM 1001.
    *   **Change:**
        ```nginx
        upstream portainer_service {
            server 10.0.0.101:9443;
        }
        ```

*   **Task 1.3: Configure Firewall Rules for Nginx Gateway**
    *   **File:** `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`
    *   **Action:** Add a firewall rule to the configuration for LXC 101 to allow outbound traffic to VM 1001 on port 9443. This will enable the Nginx gateway to proxy requests to the Portainer service.

### Phase 2: Automation & Deployment

This phase involves preparing the necessary files and updating the automation scripts to handle the deployment of the Portainer service.

*   **Task 2.1: Prepare Portainer Configuration**
    *   **Action:** Copy the existing `usr/local/phoenix_hypervisor/persistent-storage/portainer` directory to the persistent storage location for VM 1001 on the hypervisor (`/quickOS/vm-persistent-data/1001/`). This directory contains the `docker-compose.yml` file that defines the Portainer service.

*   **Task 2.2: Enhance Docker Feature Script**
    *   **File:** `usr/local/phoenix_hypervisor/bin/vm_features/feature_install_docker.sh`
    *   **Action:** Modify the script to automatically discover and run any `docker-compose.yml` files found in the root of the VM's persistent storage directory. This will ensure that the Portainer service is automatically started when the Docker feature is applied.

### Phase 3: Validation and Handoff

This phase focuses on verifying the successful deployment of the Portainer service and preparing for the handoff to the implementation team.

*   **Task 3.1: Trigger Orchestration**
    *   **Action:** Run the `phoenix-cli` orchestrator to apply all the declarative configuration changes and trigger the updated automation scripts.

*   **Task 3.2: Verify Accessibility**
    *   **Action:** Access the Portainer UI in a web browser at `https://portainer.phoenix.local` to confirm that the Nginx gateway is correctly routing traffic to the service.

*   **Task 3.3: Verify Data Persistence**
    *   **Action:** Create a test object in the Portainer UI (e.g., a new user or endpoint) and then restart the Portainer container. Verify that the object still exists after the restart, confirming that data is being correctly persisted to the dedicated NFS volume.

*   **Task 3.4: Handoff to Implementation**
    *   **Action:** Request a switch to 'code' mode to begin the implementation of this plan.

## 3. Conclusion

By following this plan, we will deploy Portainer in a way that is secure, robust, and fully integrated with the existing declarative infrastructure of the Phoenix Hypervisor. This will provide a powerful tool for managing the Docker environments while adhering to the core architectural principles of the project.