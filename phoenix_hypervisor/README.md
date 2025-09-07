---
title: Document Title
summary: A brief, one-to-two-sentence summary of the document's purpose and content.
document_type: Strategy | Technical | Business Case | Report
status: Draft | In Review | Approved | Archived
version: 1.0.0
author: Author Name
owner: Team/Individual Name
tags: []
review_cadence: Annual | Quarterly | Monthly | None
last_reviewed: YYYY-MM-DD
---
# Phoenix Hypervisor

### Project Summary: Phoenix Hypervisor

The Phoenix Hypervisor project is an automated system for provisioning Proxmox LXC containers and managing the hypervisor itself. It leverages a combination of shell scripts and JSON configuration files to create a stateless, idempotent, and highly customizable deployment pipeline, specifically tailored for AI and machine learning workloads.

**Key Architectural Features:**

*   **Stateless Orchestration:** The main orchestrator script, [`phoenix_orchestrator.sh`](phoenix_hypervisor/bin/phoenix_orchestrator.sh), is designed to be stateless and idempotent, ensuring resilient and repeatable deployments.
*   **Declarative Configuration:** All container and hypervisor specifications are defined in well-structured JSON files, providing a single source of truth for the entire system.
*   **Hierarchical Templates and Cloning:** The system employs a multi-layered templating strategy, allowing for the creation of a base template with subsequent templates layered on top, minimizing duplication and ensuring consistency.
*   **Modular Feature Installation:** The feature installation process is highly modular, with each feature (e.g., `base_setup`, `docker`, `nvidia`) encapsulated in its own script, making it easy to add or modify features.

**Dual-Mode Operation:**

The [`phoenix_orchestrator.sh`](phoenix_hypervisor/bin/phoenix_orchestrator.sh) script operates in two primary modes:

*   **Hypervisor Setup (`--setup-hypervisor`):** This mode is responsible for the initial configuration of the Proxmox host itself. It reads its configuration from `hypervisor_config.json` and executes a series of modular scripts to set up storage, networking, users, and other system-level features.
*   **LXC Provisioning:** This is the original mode of operation, which focuses on creating and configuring LXC containers based on definitions in `phoenix_lxc_configs.json`.

**Usage:**

*   **Hypervisor Setup:**
    ```bash
    ./bin/phoenix_orchestrator.sh --setup-hypervisor
    ```
*   **LXC Container Provisioning:**
    ```bash
    ./bin/phoenix_orchestrator.sh <CTID>
    ```

**Directory Structure:**

*   `/bin`: Contains the main orchestrator script and subdirectories for hypervisor and LXC setup scripts.
*   `/etc`: Contains all JSON configuration files and their corresponding schemas.
*   `/project_documents`: Contains all project-related documentation, including architecture summaries, implementation plans, and workflow diagrams.

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

*   [`phoenix_orchestrator.sh`](phoenix_hypervisor/bin/phoenix_orchestrator.sh): The unified main entry point for the system, orchestrating both initial hypervisor setup and container provisioning.
*   `/bin/hypervisor_setup/`: Contains scripts for initial hypervisor setup and feature installations (e.g., `hypervisor_initial_setup.sh`, `hypervisor_feature_install_nvidia.sh`).
*   `/bin/lxc_setup/`: Contains feature scripts for LXC container customization (e.g., `phoenix_hypervisor_feature_install_base_setup.sh`, `phoenix_hypervisor_feature_install_docker.sh`).
*   `phoenix_hypervisor_lxc_<CTID>.sh`: Optional, container-specific application scripts (e.g., `phoenix_hypervisor_lxc_950.sh`).

#### 3. Library Functions

Place this library file in `/usr/local/phoenix_hypervisor/bin/`.

*   [`phoenix_hypervisor_common_utils.sh`](phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh): A library of shared functions for logging, error handling, and interacting with Proxmox (`pct`) and `jq`. It is sourced by all other scripts to ensure a consistent execution environment.

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
6.  **Run Orchestrator:** Execute `./bin/phoenix_orchestrator.sh` to start the automated creation and configuration process.
7.  **Access Services:** Once complete, access services like Portainer using the configured IPs and ports.

## Contributing

This project provides a robust architectural foundation. Contributions to implement the script logic, enhance documentation, or add new features are welcome.
