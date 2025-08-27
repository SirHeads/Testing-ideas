# Phoenix Hypervisor - AI Toolbox Orchestrator - Project Overview

## Goal
Automate the creation and configuration of a suite of LXC containers on a Proxmox server, specifically tailored for AI workloads, using a centralized JSON configuration system.

## Core Components & Workflow

### 1. Configuration Files
*   `phoenix_hypervisor_config.json`: Defines system-wide settings for the orchestration environment (paths, network defaults, Proxmox defaults, behavior flags).
*   `phoenix_lxc_configs.json`: Defines the specific configuration for each LXC container to be created (resources, network, GPU assignment, roles like Portainer server/agent, specific AI model details).

### 2. Orchestrator Script (`phoenix_establish_hypervisor.sh`)
*   **Entry Point:** The main script invoked by the user.
*   **Initialization:** Validates configuration files against their schemas. Calls the initial Proxmox setup function/script.
*   **Iteration & Delegation:** Reads the `phoenix_lxc_configs.json` file. For each defined LXC container:
    *   Calls `phoenix_hypervisor_create_lxc.sh` to create the base container with specified resources.
    *   Waits for the container to be fully online and accessible.
    *   Conditionally calls `phoenix_hypervisor_lxc_nvidia.sh` if `gpu_assignment` is not "none".
    *   Conditionally calls `phoenix_hypervisor_lxc_docker.sh` if `features` indicate nesting.
    *   Looks for and executes a container-specific setup script (`phoenix_hypervisor_setup_<container_name_or_id>.sh`) if it exists.
*   **Execution Context:** Likely uses `pct` commands for container creation and management, and `pct exec` or SSH to run setup scripts inside containers.

### 3. Supporting Scripts & Functions
*   **`phoenix_hypervisor_initial_setup.sh`**: Performs one-time checks and installations on the Proxmox host (e.g., ensuring `jq`, `curl`, `ssh` utilities, schema validation tools like `ajv` are present).
*   **`phoenix_hypervisor_create_lxc.sh`**: Handles the `pct create` command and related steps to instantiate a container based on the configuration block passed by the orchestrator.
*   **`phoenix_hypervisor_lxc_nvidia.sh`**: Configures NVIDIA drivers, CUDA, and tools (`nvidia-smi`, `nvtop`) inside a specified LXC container, ensuring GPU access based on its `gpu_assignment`.
*   **`phoenix_hypervisor_lxc_docker.sh`**: Installs and configures Docker Engine, NVIDIA Container Toolkit, and potentially integrates the container with the Portainer setup inside the LXC.
*   **`phoenix_hypervisor_setup_<name/id>.sh`**: Optional, container-specific customization scripts for unique requirements (e.g., pulling a specific AI model, setting up a particular service).
*   **`/usr/local/phoenix_hypervisor/lib/*.sh`**: A library of common functions (logging, error handling, configuration parsing utilities, robust `pct exec`/SSH wrappers) sourced by the main scripts.

## Key Features
*   **Configuration-Driven:** All aspects of container creation and setup are defined in JSON.
*   **Modular Design:** Clear separation of concerns between orchestration, common setup, container creation, and specific feature setups.
*   **Conditional Logic:** Applies NVIDIA or Docker setup only when required by the container's configuration.
*   **Multi-GPU Support:** Handles containers assigned to specific GPUs or multiple GPUs.
*   **NVIDIA/CUDA Standardization:** Ensures consistent driver and toolkit versions across GPU-enabled containers.
*   **Portainer Integration:** Sets up containers as either a Portainer server or agent for centralized management.
*   **Extensible:** Allows for specific container customization via optional, named scripts.