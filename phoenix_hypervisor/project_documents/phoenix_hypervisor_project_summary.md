# `Phoenix Hypervisor` - Project Overview

## Goal

Automate the creation and configuration of a suite of LXC containers on a Proxmox server, specifically tailored for AI workloads, using a centralized JSON configuration system. Optimizes creation time through a hierarchical ZFS snapshot template strategy.

## Core Components & Workflow

### 1. Configuration Files

*   `phoenix_hypervisor_config.json`: Defines system-wide settings for the orchestration environment (paths, network defaults, Proxmox defaults, behavior flags).
*   `phoenix_lxc_configs.json`: Defines the specific configuration for each LXC container or template to be created/cloned. Includes resources, network, GPU assignment, roles (e.g., Portainer), AI model details, and snapshot template metadata (`is_template`, `template_snapshot_name`, `clone_from_template_ctid`).

### 2. Orchestrator Script (`phoenix_establish_hypervisor.sh`)

*   **Entry Point:** The main script invoked by the user.
*   **Initialization:** Validates configuration files against their schemas. Calls the initial Proxmox setup function/script.
*   **Iteration & Processing:** Reads the `phoenix_lxc_configs.json` file. Processes containers/templates, generally in ascending CTID order to respect dependencies.
    *   **If `is_template` is true:**
        *   Clones from the specified source template (using `clone_from_template_ctid`) or creates from scratch (for the base template).
        *   Waits for the new template container to be fully online and accessible.
        *   Conditionally configures NVIDIA/Docker based on its specific requirements.
        *   Executes its specific setup script (e.g., `phoenix_hypervisor_setup_902.sh`), which typically finalizes the environment and creates the ZFS snapshot defined by `template_snapshot_name`.
    *   **If `is_template` is false (a standard container):**
        *   Determines the most suitable existing template snapshot to clone from based on its configuration requirements (e.g., needs GPU, needs Docker) or uses an explicitly defined `clone_from_template_ctid`.
        *   Calls a new internal function/script to perform `pct clone`, creating the container with settings from its specific `config_block`.
        *   Waits for the container to be fully online and accessible.
        *   Looks for and executes a container-specific setup script (`phoenix_hypervisor_setup_<CTID>.sh`) for final, unique configuration.
    *   **Finalization for All Containers/Templates:**
        *   Shuts down the container/template.
        *   Takes a final "configured-state" ZFS snapshot.
        *   Restarts the container/template.
*   **Execution Context:** Uses `pct` commands for container creation, cloning, management, and snapshotting. Uses `pct exec` or SSH to run setup scripts inside containers.

### 3. Supporting Scripts & Functions

*   **`phoenix_hypervisor_initial_setup.sh`**: Performs one-time checks and installations on the Proxmox host (e.g., ensuring `jq`, `curl`, `ssh` utilities, schema validation tools like `ajv` are present).
*   **`phoenix_hypervisor_create_lxc.sh`**: Handles the `pct create` command for containers not created via cloning.
*   **`phoenix_hypervisor_clone_lxc.sh`**: Handles the `pct clone` command and related steps to instantiate a container from a specified template snapshot.
*   **`phoenix_hypervisor_lxc_common_nvidia.sh`**: Configures NVIDIA drivers, CUDA, and tools (`nvidia-smi`, `nvtop`) inside a specified LXC container, ensuring GPU access based on its `gpu_assignment`.
*   **`phoenix_hypervisor_lxc_common_docker.sh`**: Installs and configures Docker Engine, NVIDIA Container Toolkit, and potentially integrates the container with the Portainer setup inside the LXC.
*   **`phoenix_hypervisor_setup_<CTID>.sh`**: Container/template-specific customization scripts. For templates, these scripts finalize the environment and create the template snapshot. For standard containers, they perform unique setup tasks.
*   **`/usr/local/phoenix_hypervisor/lib/*.sh`**: A library of common functions (logging, error handling, configuration parsing utilities, robust `pct` command wrappers) sourced by the main scripts.

## Key Features

*   **Configuration-Driven:** All aspects of container creation and setup are defined in JSON.
*   **Modular Design:** Clear separation of concerns between orchestration, common setup, container creation/cloning, and specific feature setups.
*   **Snapshot-Based Templates:** Dramatically reduces container creation time by cloning from pre-configured ZFS snapshots. Supports a hierarchical template chain (Base OS -> Base+Docker -> Base+vLLM).
*   **Conditional Logic & Intelligent Cloning:** Applies NVIDIA or Docker setup only when required. The orchestrator intelligently selects the best base snapshot for cloning standard containers.
*   **Multi-GPU Support:** Handles containers assigned to specific GPUs or multiple GPUs.
*   **NVIDIA/CUDA Standardization:** Ensures consistent driver and toolkit versions across GPU-enabled containers.
*   **Portainer Integration:** Sets up containers as either a Portainer server or agent for centralized management.
*   **Extensible:** Allows for specific container customization via optional, CTID-named scripts.
*   **Idempotency & Final Snapshots:** Checks for existing containers/templates and skips creation if found. Takes a final "configured-state" snapshot for all containers.