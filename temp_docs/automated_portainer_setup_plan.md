# Automated Portainer Setup Plan

This document outlines the plan to automate the initial setup of a Portainer container within VM 1001, ensuring a pre-configured admin user and persistent settings for repeatable deployments.

## Phase 1: Configuration and Initial Setup

1.  **Create `portainer-config` Directory**: A new directory will be created at `usr/local/phoenix_hypervisor/etc/portainer-config` to store all Portainer-related configurations.
2.  **Create `docker-compose.yml`**: A `docker-compose.yml` file will be created in the new directory to define the Portainer service, as described in the consultant's report.
3.  **Update `phoenix_vm_configs.json`**: A new section will be added to `phoenix_vm_configs.json` for VM 1001 to define the Portainer configuration, including the admin password hash and the path to the `docker-compose.yml` file.

## Phase 2: Scripting and Automation

1.  **Create `feature_install_portainer.sh`**: A new script will be created at `usr/local/phoenix_hypervisor/bin/vm_features/feature_install_portainer.sh` to handle the automated Portainer setup.
2.  **Modify `feature_install_docker.sh`**: The existing `feature_install_docker.sh` script will be modified to call the new `feature_install_portainer.sh` script.
3.  **Implement Configuration Reading**: Logic will be implemented in `feature_install_portainer.sh` to read the Portainer configuration from `phoenix_vm_configs.json`.
4.  **Implement File Copy**: Functionality will be added to `feature_install_portainer.sh` to copy the `docker-compose.yml` file to the persistent storage of VM 1001.
5.  **Implement Service Start**: Logic will be added to `feature_install_portainer.sh` to execute `docker-compose up -d` within the VM to start the Portainer service.

## Phase 3: API Integration (Future Work)

1.  **Create Placeholder Script**: A placeholder script will be created for future Portainer API interactions, as described in the consultant's report.

## Phase 4: Documentation and Finalization

1.  **Create Documentation**: This document will serve as the official documentation for the new automated Portainer setup process.
2.  **Add Workflow Diagram**: A Mermaid diagram will be added to this document to illustrate the new workflow.

## Workflow Diagram

```mermaid
graph TD
    A[phoenix-cli] --> B[vm-manager.sh];
    B --> C["feature_install_docker.sh (in VM)"];
    C --> D["feature_install_portainer.sh (in VM)"];
    D --> E["Read Portainer config from phoenix_vm_configs.json"];
    E --> F["Copy docker-compose.yml to persistent storage"];
    F --> G["Run 'docker-compose up -d'"];
    G --> H["Portainer container is running with pre-configured admin"];