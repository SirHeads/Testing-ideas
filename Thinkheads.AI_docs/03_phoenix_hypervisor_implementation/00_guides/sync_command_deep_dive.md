# Phoenix Sync Command: A Deep Dive

## 1. Introduction

The `phoenix sync` command is a powerful and versatile tool for synchronizing the state of the Phoenix Hypervisor with its declarative configuration files. It embodies a **convention-over-configuration** approach, where the system automatically discovers and deploys Docker stacks based on a simple and intuitive directory structure. This design minimizes manual configuration, enhances reliability, and makes adding new services effortless.

## 2. The `sync` Workflow

The `sync` workflow is a multi-stage process that is both idempotent and convergent. It ensures that the live system always reflects the desired state defined in the configuration files.

1.  **Dispatch**: The `phoenix-cli` script dispatches the `sync all` task to the `portainer-manager.sh` script.
2.  **System Readiness Checks**: The `portainer-manager.sh` script performs a series of health checks to ensure that all necessary system components (DNS, Traefik, Step-CA, etc.) are running and available before proceeding.
3.  **Core Infrastructure Sync**: The script synchronizes core infrastructure, including DNS records and firewall rules, based on the declarative configurations in the `/usr/local/phoenix_hypervisor/etc/` directory.
4.  **Stack Discovery**: The script scans the `/usr/local/phoenix_hypervisor/stacks/` directory to discover all available Docker stacks. Each subdirectory is treated as a self-contained stack.
5.  **Portainer and Docker Stacks Sync**: The script reads the `phoenix_vm_configs.json` file to determine which stacks should be deployed to which VMs. It then iterates through each VM and deploys the assigned stacks using the Portainer API.
6.  **Final Traefik Sync**: The script performs a final synchronization of the Traefik proxy to ensure that it picks up any new services that were created during the stack synchronization.

## 3. Adding a New Docker Stack

Adding a new Docker stack to the system is now a simple, three-step process:

1.  **Create a Directory**: Create a new directory for your stack inside `/usr/local/phoenix_hypervisor/stacks/`. The name of this directory will be the unique identifier for your stack.
    ```bash
    mkdir -p /usr/local/phoenix_hypervisor/stacks/my-new-app
    ```
2.  **Add Configuration Files**: Inside the new directory, add two files:
    *   `docker-compose.yml`: Your standard Docker Compose file.
    *   `phoenix.json`: A manifest file that contains metadata for the stack, such as Traefik routing rules and firewall configurations.
3.  **Assign the Stack to a VM**: Edit the `/usr/local/phoenix_hypervisor/etc/phoenix_vm_configs.json` file and add the name of your new stack to the `docker_stacks` array for the desired VM.
    ```json
    "docker_stacks": [
        "qdrant_service",
        "my-new-app"
    ]
    ```
4.  **Run Sync**: Run `phoenix sync all`. The system will automatically discover your new stack, generate the necessary DNS and firewall rules, and deploy it to the specified VM.

## 4. `sync` Command Sequence Diagram

The following sequence diagram illustrates the updated end-to-end workflow of the `phoenix sync all` command.

```mermaid
sequenceDiagram
    actor User
    participant phoenix_cli as phoenix-cli
    participant portainer_manager as portainer-manager.sh
    participant File_System as /usr/local/phoenix_hypervisor
    participant Portainer_API as Portainer API

    User->>phoenix_cli: execute `phoenix sync all`
    phoenix_cli->>portainer_manager: dispatch `sync all`
    portainer_manager->>portainer_manager: Perform system readiness checks
    portainer_manager->>File_System: Synchronize core infrastructure (DNS, firewall)
    portainer_manager->>File_System: Discover stacks from /stacks directory
    portainer_manager->>Portainer_API: Get JWT
    portainer_manager->>Portainer_API: Synchronize Portainer endpoints
    loop For each VM with Docker stacks
        portainer_manager->>File_System: Read stack assignments from phoenix_vm_configs.json
        portainer_manager->>Portainer_API: Get endpoint ID for VM
        loop For each assigned Docker stack
            portainer_manager->>File_System: Read stack config from /stacks/[stack_name]
            portainer_manager->>Portainer_API: Synchronize stack
        end
    end