---
title: Script Guide - phoenix_hypervisor_lxc_954.sh
summary: This document provides a comprehensive guide to the `phoenix_hypervisor_lxc_954.sh` script, detailing its purpose, usage, and functionality for setting up an n8n instance using Docker.
document_type: Guide
status: Final
version: 1.0.0
author: Roo
tags:
  - Phoenix Hypervisor
  - Script Guide
  - n8n
  - LXC
  - Docker
---

# Script Guide: `phoenix_hypervisor_lxc_954.sh`

## 1. Introduction

This guide provides detailed documentation for the `phoenix_hypervisor_lxc_954.sh` script. This script is an application script designed to be executed within LXC container 954. Its primary responsibility is to install and run an n8n instance using a Docker container.

## 2. Purpose

The primary purpose of this script is to automate the setup of an n8n workflow automation tool. It handles the creation of a data directory and the deployment of the official n8n Docker container, ensuring that n8n is running and its data is persisted.

## 3. Usage

This script is not intended to be run directly by a user. It is executed automatically by the Phoenix Hypervisor orchestrator when setting up or starting LXC container 954.

### Execution Context

The script is executed inside the container (CTID 954) by the orchestrator. All commands are run with root privileges.

## 4. Script Breakdown

### Input and Configuration

The script does not take any external inputs or configuration files. Its behavior is self-contained.

### Hardcoded Variables

The script uses the following hardcoded values:

*   **Data Directory**: `/root/.n8n` - The directory where n8n data is stored within the container.
*   **Docker Image**: `n8nio/n8n` - The official Docker image for n8n.
*   **Container Name**: `n8n` - The name assigned to the Docker container.
*   **Port Mapping**: `5678:5678` - Maps the container's port 5678 to the host's port 5678.

### Main Logic Flow

The script executes the following steps in order:

1.  **Set Error Handling**: It configures the script to exit immediately if any command fails (`set -e`).
2.  **Define Logging Functions**: It defines `log_info` and `log_error` functions for standardized logging output.
3.  **Create Data Directory**: It creates the `/root/.n8n` directory to persist n8n data.
4.  **Run Docker Container**: It starts the `n8nio/n8n` Docker container with the following settings:
    *   `-d`: Detached mode.
    *   `--restart always`: Ensures the container restarts automatically.
    *   `--name n8n`: Assigns a name to the container.
    *   `-p 5678:5678`: Publishes the container's port.
    *   `-v /root/.n8n:/root/.n8n`: Mounts the data directory.
5.  **Log Success**: It prints a success message indicating the container has started.

## 5. Dependencies

*   **`docker`**: The Docker runtime must be installed and running in the container for this script to succeed.

## 6. Error Handling

The script uses `set -e`, which causes it to exit immediately if any command fails. For example, if the `docker` command fails, the script will terminate and signal an error to the orchestrator.

## 7. Customization

This script has no external customization options. To change its behavior, such as the port mapping or data directory, the script itself must be modified.