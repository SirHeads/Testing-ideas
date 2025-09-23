---
title: Script Guide - phoenix_hypervisor_lxc_953.sh
summary: This document provides a comprehensive guide to the phoenix_hypervisor_lxc_953.sh script, detailing its purpose, usage, and functionality for setting up an Nginx gateway.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Script Guide
- Nginx
- LXC
- Gateway
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Script Guide: `phoenix_hypervisor_lxc_953.sh`

## 1. Introduction

This guide provides detailed documentation for the `phoenix_hypervisor_lxc_953.sh` script. This script is an application script designed to be executed within LXC container 953. Its primary responsibility is to install, configure, and manage an Nginx web server that acts as a gateway for various backend services.

## 2. Purpose

The primary purpose of this script is to automate the setup of a secure Nginx gateway. It handles the installation of Nginx, deployment of a specific gateway configuration, management of self-signed SSL certificates, and ensures the Nginx service is running correctly. This provides a centralized and secure entry point for accessing services running in other containers.

## 3. Usage

This script is not intended to be run directly by a user. It is executed automatically by the Phoenix Hypervisor orchestrator when setting up or starting LXC container 953.

### Execution Context

The script is executed inside the container (CTID 953) by the orchestrator. All commands are run with root privileges.

## 4. Script Breakdown

### Input and Configuration

The script's behavior is primarily controlled by one external configuration source:

*   **Gateway Configuration File**: The script copies a pre-configured Nginx site file from `/tmp/phoenix_run/vllm_gateway` on the host to `/etc/nginx/sites-available/vllm_gateway` within the container. This file contains the core proxying and routing logic.

### Hardcoded Variables

The script uses the following hardcoded variables:

*   `SSL_DIR`: "/etc/nginx/ssl" - The directory where SSL certificates are stored. This path is a mount point for a shared volume, allowing certificates to be shared across containers.
*   `CERT_FILE`: "$SSL_DIR/portainer.phoenix.local.crt" - The specific certificate file used to check for the existence of the SSL certificates.

### Main Logic Flow

The script executes the following steps in order:

1.  **Set Error Handling**: It configures the script to exit immediately if any command fails (`set -e`).
2.  **Install Nginx**: It updates the package lists and installs the `nginx` package.
3.  **Deploy Configuration**: It copies the `vllm_gateway` configuration file from a temporary host location to the Nginx `sites-available` directory.
4.  **Enable Site**: It enables the `vllm_gateway` site by creating a symbolic link in the `sites-enabled` directory.
5.  **Disable Default Site**: It removes the default Nginx site to prevent conflicts.
6.  **Manage SSL Certificates**:
    *   It creates the `/etc/nginx/ssl` directory.
    *   It checks for the existence of a certificate (`portainer.phoenix.local.crt`).
    *   If the certificate does not exist, it generates self-signed certificates for `n8n.phoenix.local`, `portainer.phoenix.local`, and `ollama.phoenix.local`.
7.  **Test Configuration**: It runs `nginx -t` to validate the Nginx configuration.
8.  **Start Service**: It enables the Nginx service to start on boot and restarts it to apply the new configuration.
9.  **Health Check**: It verifies that the Nginx service is active. If not, it prints an error and exits with a non-zero status code.
10. **Log Success**: It prints a success message.
11. **Exit**: It exits with a status code of 0.

## 5. Dependencies

*   **`openssl`**: Required for generating self-signed SSL certificates.
*   **`systemctl`**: Used to manage the Nginx service.
*   **Shared Volume**: The script expects the `/etc/nginx/ssl` directory to be a mount point for a shared volume from the hypervisor host to persist SSL certificates.
*   **Gateway Configuration**: A valid Nginx configuration file must be present at `/tmp/phoenix_run/vllm_gateway` on the host during script execution.

## 6. Error Handling

The script uses `set -e`, which causes it to exit immediately if any command fails. It also includes a specific health check for the Nginx service. If the service is not active after the restart, the script will log an error message and exit with a status code of 1, signaling a failure to the orchestrator.

## 7. Customization

The primary method for customizing this script's behavior is by modifying the `vllm_gateway` configuration file on the hypervisor host before it is copied into the container. This allows for changes to routing, upstream servers, and other Nginx settings without altering the script itself.