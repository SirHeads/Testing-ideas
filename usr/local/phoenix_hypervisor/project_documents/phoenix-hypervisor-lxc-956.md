---
title: Script Guide - phoenix_hypervisor_lxc_956.sh
summary: This document provides a comprehensive guide to the phoenix_hypervisor_lxc_956.sh script, detailing its purpose, usage, and the functions it provides for installing and configuring Open WebUI.
document_type: Technical
status: Approved
version: 1.1.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Script Guide
- Open WebUI
- LXC
- Docker
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Script Guide: `phoenix_hypervisor_lxc_956.sh`

## 1. Introduction

This guide provides detailed documentation for the `phoenix_hypervisor_lxc_956.sh` script. This script automates the installation and configuration of Open WebUI within a dedicated LXC container (CTID 956). It handles everything from Docker dependencies to the final health check of the Open WebUI service.

## 2. Purpose

The primary purpose of this script is to provide a standardized and automated method for deploying Open WebUI. It ensures that the Open WebUI is set up correctly, connected to the appropriate Ollama backend, and that its data is persisted across container restarts.

## 3. Usage

This script is designed to be executed on the Proxmox host or within a context where it can manage the specified LXC container.

### Syntax

```bash
/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_956.sh
```

## 4. Script Breakdown

### Environment Setup

The script sets up a consistent environment by:
*   **Setting Shell Options**: `set -e` is used for robust error handling, ensuring that the script exits immediately on error.
*   **Defining Hardcoded Variables**: The script uses a set of hardcoded variables for the LXC ID, name, ports, and other configuration details.

### Configuration Variables

*   `LXC_ID`: The target LXC container ID, hardcoded to `956`.
*   `LXC_NAME`: The name of the LXC container, hardcoded to `openWebUIBase`.
*   `OPENWEBUI_PORT`: The port on which Open WebUI will be accessible, hardcoded to `8080`.
*   `OLLAMA_API_IP`: The IP address of the Ollama API backend, hardcoded to `10.0.0.155`.
*   `OLLAMA_API_PORT`: The port of the Ollama API backend, hardcoded to `11434`.
*   `OPENWEBUI_DATA_VOLUME`: The name of the Docker volume used for persistent data, hardcoded to `openwebui-data`.

### Functions

#### `check_docker_installation()`

*   **Description**: Checks if Docker is installed and available in the system's PATH.
*   **Arguments**: None.
*   **Returns**: Exits with status 1 if Docker is not found.

#### `pull_openwebui_image()`

*   **Description**: Pulls the official Open WebUI Docker image from `ghcr.io`.
*   **Arguments**: None.
*   **Returns**: None. Exits with a non-zero status if the Docker pull command fails.

#### `create_data_volume()`

*   **Description**: Creates a persistent Docker volume for Open WebUI data.
*   **Arguments**: None (uses global `OPENWEBUI_DATA_VOLUME`).
*   **Returns**: None. Exits with a non-zero status if the Docker volume creation command fails.

#### `stop_and_remove_existing_container()`

*   **Description**: Stops and removes any existing Open WebUI Docker container to ensure a clean start.
*   **Arguments**: None.
*   **Returns**: None.

#### `start_openwebui_container()`

*   **Description**: Starts the Open WebUI Docker container with the specified configurations, including port mappings, volume mounts, and the Ollama API backend URL.
*   **Arguments**: None (uses global variables).
*   **Returns**: None. Exits with a non-zero status if the Docker run command fails.

#### `perform_health_check()`

*   **Description**: Performs a health check on the Open WebUI service to ensure it is running and accessible.
*   **Arguments**: None.
*   **Returns**: Exits with status 1 if the health check fails.

#### `main()`

*   **Description**: The main entry point for the script, orchestrating the entire setup process.
*   **Arguments**: None.
*   **Returns**: Exits with status 0 on successful completion, or a non-zero status on failure.

## 5. Dependencies

*   **Docker**: Required to run the Open WebUI container.
*   **curl**: Used for the health check.
*   **hostname**: Used to display the IP address of the container.
*   **awk**: Used to parse the IP address from the `hostname` command output.

## 6. Error Handling

The script uses `set -e` to ensure that it exits immediately if any command fails. Error messages are printed to standard output, and in the case of a health check failure, the Docker container's logs are dumped for debugging purposes.

## 7. Customization

All configuration variables are hardcoded within the script. To change the LXC ID, ports, or other settings, the script itself must be modified.