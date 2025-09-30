---
title: Technology Stack
summary: This document outlines the technology stack for Thinkheads.AI, including hardware infrastructure, software stack, integration plan, and scalability considerations, with a focus on the declarative infrastructure provided by the Phoenix Hypervisor project.
document_type: Technical Strategy
status: Approved
version: 2.0.0
author: Thinkheads.AI
owner: Technical VP
tags:
  - Technology Stack
  - Strategy
  - Technical
  - Architecture
  - Proxmox
  - LXC
  - Docker
  - Nginx
  - PostgreSQL
  - Python
  - FastAPI
  - vLLM
  - Ollama
  - RAG
  - Phoenix Hypervisor
review_cadence: Quarterly
last_reviewed: 2025-09-29
---
# Technology Stack

## Overview
The Thinkheads.AI technology stack is designed to support AI-driven project development, portfolio showcasing, and efficient solo operation. It leverages a combination of local and cloud infrastructure, open-source tools, and a declarative automation framework called Phoenix Hypervisor to enable rapid learning and deployment of AI/ML/DL applications. The stack is optimized for scalability, security, and cost-efficiency, aligning with the goal of building a job-ready portfolio in artificial intelligence.

## Declarative Infrastructure with Phoenix Hypervisor
The cornerstone of our technical strategy is the Phoenix Hypervisor project, a sophisticated, automated system for provisioning Proxmox LXC containers and Virtual Machines (VMs). It leverages a combination of shell scripts and JSON configuration files to create a stateless, idempotent, and highly customizable deployment pipeline.

- **`phoenix_orchestrator.sh`**: The single point of entry for all provisioning and management tasks. It reads from the configuration files to create, configure, and manage the entire lifecycle of the virtualized infrastructure.
- **`phoenix_hypervisor_config.json`**: Defines the global settings for the Proxmox environment, including networking, storage (ZFS), and shared volumes.
- **`phoenix_lxc_configs.json`**: Provides detailed configurations for each LXC container, specifying resources, features (e.g., Docker, NVIDIA, vLLM, Ollama), and application-specific scripts.
- **`phoenix_vm_configs.json`**: Defines the configurations for virtual machines, including their source templates and features.

This declarative approach ensures that our infrastructure is reproducible, version-controlled, and can be easily modified and extended.

## Hardware Infrastructure
- **Local Proxmox Server**:
  - **Specifications**: AMD 7700 CPU, 96 GB DDR5 RAM, dual RTX 5060 Ti GPUs, NVMe storage (1 TB).
  - **Role**: Hosts compute-intensive tasks, including LLM hosting (vLLM, Ollama), image processing, and development environments.
  - **Configuration**:
    - Proxmox VE for virtualization.
    - LXC containers for hosting AI/ML workloads and services, with resources and features defined in `phoenix_lxc_configs.json`.
    - VMs for development environments with GPU passthrough for interactive development.
- **Linode Cloud Server**:
  - **Specifications**: 4 GB RAM, 2 CPU cores, 80 GB SSD storage, Debian OS.
  - **Role**: Hosts public-facing Thinkheads.AI website and lightweight services.
  - **Configuration**: Docker for production/test environments, Nginx for web serving, Cloudflare Tunnel for secure access.

## Software Stack
- **Proxmox VE**:
  - **Role**: Virtualization platform for the local server.
  - **Usage**: Manages LXC containers and VMs, allocates GPU resources for ML tasks, and supports isolated environments for production and testing, all orchestrated by the Phoenix Hypervisor.
- **LXC**:
    - **Role**: Lightweight containerization for isolating services and applications.
    - **Usage**: Used extensively on the Proxmox server to run various services, including Docker, vLLM, Ollama, and Nginx. Configurations are managed declaratively through `phoenix_lxc_configs.json`.
- **Docker**:
  - **Role**: Application containerization.
  - **Usage**: Deployed as a feature within LXC containers to run applications like Portainer and other services. This nested virtualization approach provides a flexible and scalable environment for application deployment.
- **Nginx**:
  - **Role**: Web server and reverse proxy.
  - **Usage**: Serves the static Hugo site on Linode and acts as a reverse proxy for services running in LXC containers on the Proxmox server. Configuration is managed through the Phoenix Hypervisor, with site configurations stored in the project repository.
- **PostgreSQL**:
  - **Role**: Database for storing user data, project metadata, and RAG embeddings.
  - **Usage**: Deployed within an LXC container, its configuration and management are handled at the application level.
- **Python/FastAPI**:
  - **Role**: Backend API development.
  - **Usage**: Powers the backend APIs for various projects. The FastAPI application is containerized and deployed within an LXC container.
- **vLLM & Ollama**:
  - **Role**: Local LLM hosting for AI-driven features and RAG.
  - **Usage**: Deployed as features within dedicated LXC containers with GPU passthrough. Their configurations, including model selection and operational parameters, are managed declaratively in `phoenix_lxc_configs.json`.
- **Cloudflare**:
  - **Role**: DNS management, DDoS protection, and secure access.
  - **Usage**: Manages DNS for Thinkheads.AI and provides a secure tunnel to the Linode server.
- **Git**:
  - **Role**: Version control for code, configuration, and documentation.
  - **Usage**: The entire Phoenix Hypervisor project, including all configuration files and scripts, is stored in a Git repository, enabling versioning and collaborative development.

## Integration Plan
- **Declarative Provisioning**: The `phoenix_orchestrator.sh` script reads the JSON configuration files to provision and configure the entire infrastructure, from the hypervisor itself to the individual LXC containers and VMs.
- **AI/ML Workloads**: vLLM and Ollama are deployed as features within LXC containers, with their models and configurations managed by the Phoenix Hypervisor.
- **Development Workflow**: Developers can modify the JSON configuration files to change the infrastructure, add new services, or update existing ones. These changes are then applied by running the `phoenix_orchestrator.sh` script.

## Scalability and Constraints
- **Scalability**: The declarative nature of the Phoenix Hypervisor allows for easy scaling of the infrastructure. New containers and VMs can be added by simply defining them in the configuration files.
- **Constraints**: The primary constraints are the hardware resources of the local Proxmox server. As the number of services and AI/ML workloads grows, it may be necessary to upgrade the hardware.

## Success Metrics
- **Operational Stability**: Achieve 99.9% uptime for all services, managed and monitored through the Phoenix Hypervisor.
- **Performance**: Maintain high performance for AI/ML workloads, with LLM response times under 2 seconds.
- **Automation**: Automate 95% of infrastructure management tasks through the Phoenix Hypervisor.
- **Portfolio Readiness**: Deploy and manage all project components through the declarative infrastructure provided by the Phoenix Hypervisor.
