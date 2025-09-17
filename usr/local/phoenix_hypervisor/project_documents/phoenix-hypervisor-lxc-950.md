---
title: Script Guide - phoenix_hypervisor_lxc_950.sh
summary: This document provides a comprehensive guide to the `phoenix_hypervisor_lxc_950.sh` script, detailing its purpose, usage, and the functions it provides.
document_type: Guide
status: Final
version: 1.0.0
author: Roo
tags:
  - Phoenix Hypervisor
  - Script Guide
  - vLLM
  - LXC
---

# Script Guide: `phoenix_hypervisor_lxc_950.sh`

## 1. Introduction

This guide provides detailed documentation for the `phoenix_hypervisor_lxc_950.sh` script. This script is designed to manage the deployment and lifecycle of a vLLM (Vector Large Language Model) API server within a dedicated LXC container (CTID 950). It automates the process of configuring the environment, generating systemd service files, and managing the vLLM service to ensure it runs correctly and efficiently.

## 2. Purpose

The primary purpose of this script is to provide a reliable and automated method for deploying and managing a vLLM API server. It standardizes the setup process, handles dynamic configuration, and includes robust health checks and API validation to ensure the service is fully operational.

## 3. Usage

This script is intended to be executed on the Proxmox host to manage the vLLM container. It requires the CTID of the target container as a command-line argument.

### Syntax

```bash
/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_950.sh <CTID>
```

### Arguments

*   `<CTID>`: The numeric ID of the LXC container where the vLLM server is to be managed.

## 4. Script Breakdown

### Input and Configuration

The script relies on several inputs and configuration sources:

*   **Command-Line Arguments**: The CTID of the target LXC container must be provided as the first argument.
*   **LXC Configuration File**: The script retrieves vLLM-specific parameters from the `phoenix_lxc_configs.json` file. These parameters include:
    *   `.vllm_model`: The name or path of the model to be loaded.
    *   `.vllm_tensor_parallel_size`: The tensor parallel size for the model.
    *   `.vllm_gpu_memory_utilization`: The GPU memory utilization limit.
    *   `.vllm_max_model_len`: The maximum model length.
    *   `.network_config.ip`: The IP address of the container.

### Functions

#### `parse_arguments(CTID)`

*   **Description**: Parses the command-line arguments to ensure exactly one argument (the CTID) is provided.
*   **Behavior**: Exits with an error if the number of arguments is incorrect.

#### `configure_and_start_systemd_service()`

*   **Description**: Dynamically configures and starts the vLLM systemd service within the container.
*   **Actions**:
    1.  Retrieves vLLM parameters from the configuration file.
    2.  Constructs the necessary arguments for the vLLM server.
    3.  Replaces placeholders in a template systemd service file (`/etc/systemd/system/vllm_model_server.service`) with the retrieved configuration values.
    4.  Reloads the systemd daemon, enables the service to start on boot, and restarts it.
    5.  Verifies that the service has started successfully.

#### `perform_health_check()`

*   **Description**: Performs a health check to ensure the vLLM API server is responsive.
*   **Actions**:
    1.  Continuously sends requests to the `/health` endpoint of the API server.
    2.  Retries up to 30 times with a 10-second interval between attempts.
    3.  If the health check fails after all attempts, it logs the recent service logs for diagnosis and exits with a fatal error.

#### `validate_api_with_test_query()`

*   **Description**: Sends a test query to the vLLM API to validate that the model is loaded and generating valid responses.
*   **Actions**:
    1.  Constructs a JSON payload for a chat completion request.
    2.  Sends the request to the `/v1/chat/completions` endpoint.
    3.  Checks the response for errors and validates that it contains a valid message content.
    4.  Logs a snippet of the response on success or exits with a fatal error on failure.

#### `display_connection_info()`

*   **Description**: Displays the final connection details for the vLLM API server.
*   **Output**:
    *   IP Address and Port.
    *   The name of the loaded model.
    *   An example `curl` command for interacting with the API.

#### `main()`

*   **Description**: The main entry point of the script.
*   **Orchestration**: Calls the functions in the following order:
    1.  `parse_arguments`
    2.  `configure_and_start_systemd_service`
    3.  `perform_health_check`
    4.  `validate_api_with_test_query`
    5.  `display_connection_info`

## 5. Dependencies

*   **`phoenix_hypervisor_common_utils.sh`**: Must be sourced for common utility functions (logging, error handling, etc.).
*   **`jq`**: Required for parsing the JSON configuration file.
*   **`curl`**: Used for performing health checks and API validation.
*   **`systemctl`**: Used within the container to manage the systemd service.

## 6. Error Handling

The script incorporates robust error handling:

*   **Strict Mode**: Uses `set -e` and `set -o pipefail` to ensure that the script exits immediately if any command fails.
*   **Logging**: Uses the `log_error` and `log_fatal` functions from the common utilities to provide clear error messages.
*   **Health Checks**: The `perform_health_check` function includes a retry mechanism and provides diagnostic logs upon failure.
*   **API Validation**: The `validate_api_with_test_query` function checks for errors in the API response to ensure the model is functioning correctly.

## 7. Customization

The behavior of the script is primarily customized through the `phoenix_lxc_configs.json` file. By modifying the vLLM-related parameters for the specific container, you can change the model, tensor parallel size, and other settings without altering the script itself.