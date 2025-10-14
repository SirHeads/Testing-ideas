# Test Plan: VM and Portainer Workflow Validation

## 1. Objective

This test plan outlines the procedures to validate the end-to-end workflow for creating Virtual Machines (VMs), deploying Portainer, and synchronizing Docker stacks within the Phoenix Hypervisor ecosystem. The primary goal is to ensure that the recent architectural changes, including the integration of a centralized Step-CA and a declarative, state-driven orchestration model, are functioning correctly.

## 2. Test Environment

*   **Hypervisor**: Proxmox VE
*   **Orchestration CLI**: `phoenix-cli`
*   **Networking**: Three-tiered model with Nginx, Traefik, and Step-CA
*   **Target VMs**:
    *   VM 1001 (Portainer Server)
    *   VM 1002 (Portainer Agent / drphoenix)

## 3. Test Cases

### 3.1. VM Creation and Docker Installation

*   **Test Case 1.1**: Create Portainer Server VM (1001)
    *   **Command**: `phoenix-cli create 1001`
    *   **Expected Result**:
        *   VM 1001 is created successfully.
        *   The `base_setup` and `docker` features are applied.
        *   The Docker daemon is running and trusts the internal Step-CA.
*   **Test Case 1.2**: Create Portainer Agent VM (1002)
    *   **Command**: `phoenix-cli create 1002`
    *   **Expected Result**:
        *   VM 1002 is created successfully.
        *   The `base_setup` and `docker` features are applied.
        *   The Docker daemon is running and trusts the internal Step-CA.

### 3.2. Portainer Environment Synchronization

*   **Test Case 2.1**: Synchronize Portainer Environment
    *   **Command**: `phoenix-cli sync portainer`
    *   **Expected Result**:
        *   The `portainer-manager.sh` script executes without errors.
        *   The Portainer server is deployed in VM 1001.
        *   The Portainer agent is deployed in VM 1002.
        *   The Portainer server successfully creates an environment (endpoint) for the agent in VM 1002.
        *   Communication between the server and agent is secured with certificates from the internal Step-CA.

### 3.3. Declarative Stack Deployment

*   **Test Case 3.1**: Verify Qdrant Stack Deployment
    *   **Prerequisite**: Test Case 2.1 is successful.
    *   **Verification Steps**:
        1.  Log in to the Portainer UI.
        2.  Navigate to the `drphoenix` environment.
        3.  Verify that the `qdrant_service` stack is running.
        4.  Verify that the Qdrant container is running and healthy.
*   **Test Case 3.2**: Verify Stack Accessibility via Traefik
    *   **Prerequisite**: Test Case 3.1 is successful.
    *   **Verification Steps**:
        1.  From within the hypervisor, attempt to access the Qdrant service via its internal Traefik-managed hostname (e.g., `curl https://qdrant.internal.thinkheads.ai`).
        2.  **Expected Result**: A successful response from the Qdrant service, with a valid SSL certificate issued by the internal Step-CA.

## 4. Test Execution

The tests will be executed sequentially, as outlined above. Each test case must pass before proceeding to the next. Any failures will be logged, and the implementation will be reviewed and corrected before re-executing the tests.