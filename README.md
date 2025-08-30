# Phoenix Hypervisor

## Overview

Phoenix Hypervisor is a comprehensive automation framework designed for Proxmox Virtual Environment (PVE). It streamlines the creation, configuration, and management of LXC containers specifically tailored for AI and machine learning workloads. Leveraging ZFS snapshots for rapid provisioning and a centralized JSON configuration system, Phoenix Hypervisor ensures consistency, reproducibility, and scalability across your containerized AI infrastructure.

The system establishes a hierarchical chain of base templates: Base OS (CTID 900) -> Base+GPU (CTID 901) / Base+Docker (CTID 902) -> Base+Docker+GPU (CTID 903) -> Base+vLLM (CTID 920). Application containers (like Portainer or specific vLLM model servers) are then rapidly cloned from these optimized snapshots, significantly reducing setup times.

## Key Features

*   **Configuration-Driven:** All aspects of container creation and setup are defined in structured JSON files (`phoenix_hypervisor_config.json`, `phoenix_lxc_configs.json`).
*   **Snapshot-Based Templates:** Uses ZFS snapshots to create a hierarchical chain of base templates (Base OS, Base+GPU, Base+Docker, Base+Docker+GPU, Base+vLLM), enabling ultra-fast cloning of new containers. The hierarchy is: Base OS (CTID 900) -> Base+GPU (CTID 901) / Base+Docker (CTID 902) -> Base+Docker+GPU (CTID 903) -> Base+vLLM (CTID 920).
*   **Modular Design:** Orchestrated by a main script (`phoenix_establish_hypervisor.sh`) that calls dedicated sub-scripts for specific tasks (creation, cloning, NVIDIA setup, Docker setup, container-specific customization).
*   **Conditional Logic:** Applies NVIDIA or Docker setup only when required by a container's configuration.
*   **Multi-GPU Support:** Handles containers assigned to specific GPUs or multiple GPUs.
*   **NVIDIA/CUDA Standardization:** Ensures consistent driver and toolkit versions across GPU-enabled containers.
*   **Integrated Tooling:** Sets up containers as Portainer Agents or Servers for centralized Docker management.
*   **Extensible:** Allows for specific container customization via optional, CTID-named scripts (`phoenix_hypervisor_setup_<CTID>.sh`).
*   **Idempotency & Final Snapshots:** Scripts are designed to be re-run safely. Every container/template takes a final `configured-state` ZFS snapshot after setup.

## Repository Structure & File Placement

This repository contains the definitions, documentation, and shell script skeletons for the Phoenix Hypervisor system. To deploy it on your Proxmox host, files need to be placed in specific directories.

**Standard Deployment Paths (Configurable in `phoenix_hypervisor_config.json`):**

*   `/usr/local/phoenix_hypervisor/bin/`: Executable scripts (`.sh`).
*   `/usr/local/phoenix_hypervisor/etc/`: Configuration files (`.json`, `.schema.json`), token files (`.conf`), and shared Docker-related files.
*   `/usr/local/phoenix_hypervisor/lib/`: Common function libraries (`.sh`) sourced by other scripts.

### File Placement Guide

#### 1. Configuration Files & Schemas

Place these files in `/usr/local/phoenix_hypervisor/etc/`.

*   `phoenix_hypervisor_config.json`: System-wide settings (paths, network defaults, Proxmox defaults, Docker image versions, behavior flags).
*   `phoenix_lxc_configs.json`: Definitions for all LXC containers and templates (resources, network, GPU assignment, roles, AI model details).
*   `phoenix_lxc_configs.schema.json`: JSON Schema for validating `phoenix_lxc_configs.json`.
*   `phoenix_hypervisor_config.schema.json`: JSON Schema for validating `phoenix_hypervisor_config.json`.
*   `phoenix_hf_token.conf`: (Create this file) Your Hugging Face API token. **Keep secure (chmod 600)**.
*   `phoenix_docker_token.conf`: (Create this file) Your Docker Hub credentials (if needed). **Keep secure (chmod 600)**.

#### 2. Orchestrator & Core Scripts

Place these executable scripts (`chmod +x`) in `/usr/local/phoenix_hypervisor/bin/`.

*   `phoenix_establish_hypervisor.sh`: The main orchestrator script.
*   `phoenix_hypervisor_initial_setup.sh`: Performs one-time checks and installations on the Proxmox host.
*   `phoenix_hypervisor_create_lxc.sh`: Handles the `pct create` command for base containers.
*   `phoenix_hypervisor_clone_lxc.sh`: Handles the `pct clone` command for creating containers from template snapshots.
*   `phoenix_hypervisor_lxc_common_nvidia.sh`: Configures NVIDIA drivers, CUDA, and tools inside a specified LXC container.
*   `phoenix_hypervisor_lxc_common_docker.sh`: Installs and configures Docker Engine, NVIDIA Container Toolkit, and potentially integrates with Portainer inside the LXC.
*   `phoenix_hypervisor_setup_<CTID>.sh`: Optional, container-specific customization scripts (e.g., `phoenix_hypervisor_setup_901.sh`, `phoenix_hypervisor_setup_910.sh`).

#### 3. Library Functions

Place this library file in `/usr/local/phoenix_hypervisor/lib/`.

*   `common_functions.sh`: *(To be created/implemente*d) A library of common functions (logging, error handling, configuration parsing utilities, robust `pct exec`/SSH wrappers) sourced by the main scripts.

*(Note: The `common_functions.sh` library was identified as a future enhancement/task for consolidating shared utilities. It is essential for a full implementation but was not explicitly created in our session.)*

#### 4. Documentation

These markdown documents provide detailed insights into the project's architecture, requirements, and workflows. They can be kept in the repository root or a dedicated `docs/` folder for easy access.

*   `README.md` (this file)
*   `phoenix_hypervisor_project_summary.md`
*   `phoenix_establish_hypervisor_summary.md`
*   `phoenix_establish_hypervisor_requirements.md`
*   `phoenix_lxc_configs_summary.md`
*   `phoenix_hypervisor_lxc_<CTID>_details.md` (e.g., `phoenix_hypervisor_lxc_900_details.md`)
*   `phoenix_hypervisor_lxc_summary.md`
*   `phoenix_hypervisor_setup_script_pattern_summary.md`
*   `phoenix_hypervisor_setup_script_pattern_requirements.md`
*   `phoenix_hypervisor_lxc_common_nvidia_summary.md`
*   `phoenix_hypervisor_lxc_common_docker_summary.md`
*   `phoenix_hypervisor_initial_setup_summary.md`
*   `phoenix_hypervisor_create_lxc_summary.md`
*   `phoenix_hypervisor_clone_lxc_summary.md`
*   `phoenix_hypervisor_lxc_nvidia_summary.md`
*   `phoenix_hypervisor_lxc_docker_summary.md`
*   `phoenix_hypervisor_project_summary_initialbuild.md`

*(Note: Shell script skeletons (`.sh` files with only comments) are also part of the repository structure and follow the placement rules for scripts/libs above.)*

## Getting Started (Conceptual)

1.  **Prepare Proxmox Host:** Ensure your Proxmox host meets prerequisites (ZFS storage, internet access).
2.  **Create Directory Structure:** Create the directories `/usr/local/phoenix_hypervisor/{bin,etc,lib}` on your Proxmox host.
3.  **Place Files:** Copy configuration files, schemas, and scripts to their respective directories as outlined above. Make scripts executable (`chmod +x /usr/local/phoenix_hypervisor/bin/*.sh`).
4.  **Configure:** Edit `phoenix_hypervisor_config.json` and `phoenix_lxc_configs.json` to match your specific environment, container definitions, and requirements.
5.  **Implement Scripts:** The `.sh` files provided are skeletons. You will need to implement the Bash logic within them based on their documented requirements.
6.  **Run Orchestrator:** Execute `./phoenix_establish_hypervisor.sh` to start the automated creation and configuration process.
7.  **Access Services:** Once complete, access services like Portainer using the configured IPs and ports.

## Contributing

This project provides a robust architectural foundation. Contributions to implement the script logic, enhance documentation, or add new features are welcome.
