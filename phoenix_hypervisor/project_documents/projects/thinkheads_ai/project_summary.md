# Project Summary: ThinkHeadsAI Hybrid Development Environment

## 1. Overview

The "ThinkHeadsAI" project aims to create a powerful and flexible hybrid development environment for building, testing, and showcasing AI-driven web technologies. The architecture is designed to optimize resources by separating GPU-intensive AI workloads from public-facing web services.

This document provides a high-level summary of the project's goals, architecture, and the new Virtual Machine (VM) management features that form a core part of its infrastructure.

## 2. Core Strategy

The project's strategy is built on the following principles:

-   **Modularity and Portability**: All web-facing services are containerized using Docker to ensure consistency across different environments.
-   **Resource Optimization**: A high-performance local server, "Phoenix," handles heavy AI computation, while a lightweight hosted server, "Rumple," manages public web traffic.
-   **Mirrored Environments**: The Phoenix server hosts three VMs that replicate the Rumple server's setup, providing isolated environments for development, testing, and production staging.
-   **Automation and Integration**: The environment leverages APIs and workflow automation tools to streamline communication between the Phoenix and Rumple servers.

## 3. Architecture at a Glance

The hybrid architecture consists of two main components:

-   **Backend (Phoenix)**: A local, high-performance server equipped with GPUs for AI tasks like model training and inference. It hosts LXC containers for management tools and VMs that mirror the frontend environment.
-   **Frontend (Rumple)**: An externally hosted server that runs the public-facing web services in Docker containers. It handles user interactions and makes API calls to the Phoenix server for AI-related tasks.

This setup allows for a cost-effective and scalable solution, where the expensive GPU resources are utilized on-demand, and the public-facing services remain lightweight and responsive.

## 4. VM Management Feature

A key enhancement to the "ThinkHeadsAI" environment is the introduction of VM creation and management capabilities within the `phoenix_orchestrator.sh` script. This feature allows for the automated setup of the mirrored development, testing, and production environments on the Phoenix server.

The new VM management functionality enables users to:

-   Define VM configurations in a central JSON file.
-   Create, start, stop, and delete VMs using simple command-line arguments.
-   Automate the post-creation setup of VMs with custom scripts.

This feature is crucial for maintaining consistency between the local and hosted environments and for streamlining the development workflow. The `usage_guide.md` provides detailed instructions on how to use these new capabilities.