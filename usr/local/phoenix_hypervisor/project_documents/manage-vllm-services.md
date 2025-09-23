---
title: Script Guide - manage_vllm_services.sh
summary: This document provides a comprehensive guide to the manage_vllm_services.sh script, detailing its purpose, usage, and functionality.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- vLLM
- Script Guide
- Service Management
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Script Guide: `manage_vllm_services.sh`

## 1. Introduction

This guide provides detailed documentation for the `manage_vllm_services.sh` script. This script is a utility designed to simplify the management of vLLM (Vector Language Model) services, specifically for starting, stopping, and checking the status of model API servers.

## 2. Purpose

The primary purpose of this script is to provide a simple command-line interface to control vLLM services. It is pre-configured to manage two specific models: an embedding model and a Qwen model, each running on a different port.

## 3. Usage

The script is executed from the command line with one of three arguments: `start`, `stop`, or `status`.

### Syntax

```bash
./manage_vllm_services.sh {start|stop|status}
```

### Arguments

*   `start`: Initializes and starts the vLLM services for both the embedding and Qwen models.
*   `stop`: Terminates the running vLLM services.
*   `status`: Checks and displays the current running status of the vLLM services.

## 4. Script Breakdown

### Configuration Variables

The script uses the following variables to define the models and ports:

*   `EMBEDDING_MODEL_NAME`: The name of the embedding model. Default: `"text-embedding-ada-002"`
*   `QWEN_MODEL_NAME`: The name of the Qwen model. Default: `"qwen-1.5-7b-chat"`
*   `EMBEDDING_PORT`: The port for the embedding model server. Default: `8000`
*   `QWEN_PORT`: The port for the Qwen model server. Default: `8001`

### Functions

*   **`start()`**:
    *   Prints a message indicating that the services are starting.
    *   The commands to start the vLLM API servers are present but commented out for safety. When active, they would launch the Python-based vLLM server for each model.

*   **`stop()`**:
    *   Uses `pkill` to find and terminate the processes corresponding to the vLLM services based on their port numbers.

*   **`status()`**:
    *   Uses `pgrep` to check for the existence of the vLLM service processes.
    *   It reports the status for each service individually, indicating whether it is running or not.

## 5. Dependencies

*   **vLLM**: The script assumes that the vLLM library is installed and accessible in the Python environment.
*   **`pkill` and `pgrep`**: These standard Linux utilities must be available on the system.

## 6. Error Handling

The script includes basic error handling for incorrect usage. If an invalid argument is provided, it displays the correct usage syntax and exits with a status code of 1.

## 7. Customization

To use this script for different models or ports, you can modify the configuration variables at the top of the file. Ensure that the model names correspond to models that are accessible to your vLLM installation.