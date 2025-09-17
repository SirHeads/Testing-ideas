---
title: Script Guide - phoenix_hypervisor_lxc_955.sh
summary: This document provides a comprehensive guide to the `phoenix_hypervisor_lxc_955.sh` script, detailing its purpose, usage, and functionality for setting up the Ollama systemd service.
document_type: Guide
status: Final
version: 1.0.0
author: Roo
tags:
  - Phoenix Hypervisor
  - Script Guide
  - Ollama
  - LXC
  - Systemd
---

# Script Guide: `phoenix_hypervisor_lxc_955.sh`

## 1. Introduction

This guide provides detailed documentation for the `phoenix_hypervisor_lxc_955.sh` script. This script is an application script designed to be executed within LXC container 955. Its primary responsibility is to configure and enable the Ollama systemd service, ensuring the Ollama API is available within the container.

## 2. Purpose

The primary purpose of this script is to automate the setup of the Ollama service. It handles the configuration of the system's PATH, creates a systemd service file for Ollama, and enables and starts the service.

## 3. Usage

This script is not intended to be run directly by a user. It is executed automatically by the Phoenix Hypervisor orchestrator when setting up or starting LXC container 955.

### Execution Context

The script is executed inside the container (CTID 955) by the orchestrator. All commands are run with root privileges. It requires a single argument, the CTID of the container.

## 4. Script Breakdown

### Input and Configuration

The script takes one command-line argument:

*   **`CTID`**: The container ID of the LXC container where the script is being executed.

### Dependencies

The script sources `phoenix_hypervisor_common_utils.sh` for logging and exit functions.

### Main Logic Flow

The script executes the following steps in order:

1.  **Set Error Handling**: It configures the script to exit immediately if any command fails (`set -e`) and to treat pipe failures as errors (`set -o pipefail`).
2.  **Source Utilities**: It sources the `phoenix_hypervisor_common_utils.sh` script to use its logging and exit functions.
3.  **Argument Check**: It verifies that exactly one argument (the `CTID`) is provided.
4.  **Configure PATH**: It creates a profile script to add `/usr/local/bin` to the system's PATH.
5.  **Create Systemd Service**: It creates a systemd service file at `/etc/systemd/system/ollama.service` with the following configuration:
    *   **`ExecStart`**: `/usr/bin/ollama serve`
    *   **`User`**: `root`
    *   **`Group`**: `root`
    *   **`Restart`**: `always`
    *   **`Environment`**: `OLLAMA_HOST=0.0.0.0:11434`
6.  **Enable and Start Service**: It reloads the systemd daemon, enables the `ollama.service` to start on boot, and restarts the service to apply the configuration.
7.  **Log Success**: It prints a success message indicating the setup is complete.

## 5. Dependencies

*   **`systemctl`**: The systemd init system must be available in the container.
*   **`ollama`**: The Ollama binary must be installed at `/usr/bin/ollama`.
*   **`phoenix_hypervisor_common_utils.sh`**: This utility script must be present in the same directory as the main script.

## 6. Error Handling

The script uses `set -e`, which causes it to exit immediately if any command fails. The `exit_script` function from `phoenix_hypervisor_common_utils.sh` is used to terminate the script with a specific exit code.

## 7. Customization

This script has no external customization options. To change its behavior, such as the Ollama host or port, the script itself must be modified.