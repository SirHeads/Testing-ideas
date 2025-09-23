---
title: Script Guide - phoenix_hypervisor_lxc_952.sh
summary: This document provides a comprehensive guide to the phoenix_hypervisor_lxc_952.sh script, detailing its purpose, usage, and functionality for managing a Qdrant vector database container.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Script Guide
- Qdrant
- Docker
- LXC
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Script Guide: `phoenix_hypervisor_lxc_952.sh`

## 1. Introduction

This guide provides detailed documentation for the `phoenix_hypervisor_lxc_952.sh` script. This script is an application script designed to be executed within LXC container 952. Its sole responsibility is to manage the lifecycle of a Qdrant vector database instance running inside a Docker container.

## 2. Purpose

The primary purpose of this script is to automate the setup and execution of a Qdrant container. It ensures that the Qdrant service is started with the correct configuration, including dynamic port mappings retrieved from a central configuration file, and that the necessary Docker network is in place. It also handles the cleanup of pre-existing Qdrant containers to ensure a clean start.

## 3. Usage

This script is not intended to be run directly by a user. It is executed automatically by the Phoenix Hypervisor orchestrator when setting up or starting LXC container 952.

### Execution Context

The script is executed inside the container (CTID 952) by the orchestrator. All commands are run using the container's native Docker installation.

## 4. Script Breakdown

### Input and Configuration

The script's behavior is primarily controlled by one external configuration source:

*   **LXC Configuration File**: The script retrieves port mappings from the `phoenix_lxc_configs.json` file using the `jq_get_value` helper function. Specifically, it looks for the `.ports[]` array for the entry corresponding to CTID 952.

### Hardcoded Variables

The script uses the following hardcoded variables:

*   `QDRANT_IMAGE`: "qdrant/qdrant:latest" - The Docker image to be used.
*   `QDRANT_CONTAINER_NAME`: "qdrant" - The name assigned to the running Docker container.
*   `DOCKER_NETWORK_NAME`: "qdrant_network" - The name of the Docker network to be created and used.

### Main Logic Flow

The script executes the following steps in order:

1.  **Source Common Utilities**: It sources `phoenix_hypervisor_common_utils.sh` to gain access to logging and other helper functions.
2.  **Network Check**: It checks if a Docker network named `qdrant_network` exists. If not, it creates it.
3.  **Container Cleanup**: It checks if a Docker container named `qdrant` already exists (either running or stopped). If it does, the script stops and removes it to prevent conflicts.
4.  **Image Pull**: It pulls the latest `qdrant/qdrant` image from Docker Hub to ensure the container is up-to-date.
5.  **Port Configuration**: It calls `jq_get_value` to read the port mappings from the central JSON configuration and constructs the necessary `-p` arguments for the `docker run` command.
6.  **Container Start**: It executes `docker run` to start a new, detached (`-d`), and auto-removing (`--rm`) Qdrant container with the configured name, network, and port mappings.
7.  **Log Success**: It logs a final message indicating that the Qdrant container has been started successfully.
8.  **Exit**: It exits with a status code of 0.

## 5. Dependencies

*   **`phoenix_hypervisor_common_utils.sh`**: Must be available in the same directory to be sourced for common utility functions (e.g., `log_info`, `jq_get_value`).
*   **`docker`**: The Docker engine must be installed and running inside the LXC container.
*   **`jq`**: Required by the `jq_get_value` function to parse the JSON configuration file.

## 6. Error Handling

The script relies on the strict error handling settings (`set -e` and `set -o pipefail`) inherited from the sourced `phoenix_hypervisor_common_utils.sh` script. This means the script will exit immediately if any command fails, preventing the system from reaching an inconsistent state. Errors are logged to standard output via the `log_info` and `log_error` functions.

## 7. Customization

The primary method for customizing this script's behavior is by modifying the `phoenix_lxc_configs.json` file. To change the ports exposed by the Qdrant container, update the `.ports[]` array for the CTID 952 entry. No direct modifications to the script are needed for port changes.