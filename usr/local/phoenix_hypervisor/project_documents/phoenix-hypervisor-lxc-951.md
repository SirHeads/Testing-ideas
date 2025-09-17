---
title: Script Guide - phoenix_hypervisor_lxc_951.sh
summary: This document provides a comprehensive guide to the `phoenix_hypervisor_lxc_951.sh` script, detailing its purpose, usage, and the functions it provides.
document_type: Guide
status: Final
version: 1.0.0
author: Roo
tags:
  - Phoenix Hypervisor
  - Script Guide
  - vLLM
  - LXC
  - Embeddings
---

# Script Guide: `phoenix_hypervisor_lxc_951.sh`

## 1. Introduction

This guide provides detailed documentation for the `phoenix_hypervisor_lxc_951.sh` script. This script is designed to manage the deployment and lifecycle of a vLLM (Vector Large Language Model) API server specifically for generating embeddings within a dedicated LXC container (CTID 951). It automates environment verification, dynamic systemd service file generation, service management, and robust health checks.

## 2. Purpose

The primary purpose of this script is to provide a standardized and automated method for deploying and managing a vLLM embedding server. It ensures a consistent setup, handles configuration dynamically from a central file, and includes comprehensive validation to confirm that the embedding model is fully operational and serving requests correctly.

## 3. Usage

This script is intended to be executed on the Proxmox host to manage the vLLM embedding container. It requires the CTID of the target container as a command-line argument.

### Syntax

```bash
/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_951.sh <CTID>
```

### Arguments

*   `<CTID>`: The numeric ID of the LXC container where the vLLM embedding server is to be managed.

## 4. Script Breakdown

### Input and Configuration

The script relies on several inputs and configuration sources:

*   **Command-Line Arguments**: The CTID of the target LXC container must be provided as the first argument.
*   **LXC Configuration File**: The script retrieves vLLM-specific parameters from the `phoenix_lxc_configs.json` file. These parameters include:
    *   `.vllm_model`: The name or path of the embedding model to be loaded.
    *   `.vllm_served_model_name`: The identifier used for the model in API requests.
    *   `.ports[0]`: The port on which the vLLM server will listen.
    *   `.vllm_args[]`: An array of additional command-line arguments for the vLLM server.
    *   `.network_config.ip`: The IP address of the container.

### Functions

#### `parse_arguments(CTID)`

*   **Description**: Parses the command-line arguments to ensure exactly one argument (the CTID) is provided.
*   **Behavior**: Exits with an error if the number of arguments is incorrect.

#### `configure_systemd_service()`

*   **Description**: Dynamically configures the vLLM systemd service within the container.
*   **Actions**:
    1.  Retrieves vLLM parameters (`model`, `served_model_name`, `port`, `vllm_args`) from the configuration file.
    2.  Replaces placeholders in the template systemd service file (`/etc/systemd/system/vllm_model_server.service`) with the retrieved configuration values.

#### `manage_vllm_service()`

*   **Description**: Enables and starts the vLLM model server systemd service.
*   **Actions**:
    1.  Reloads the systemd daemon to recognize the changes.
    2.  Enables the service to start on boot.
    3.  Restarts the service.
    4.  If the service fails to start, it logs the recent journal entries for diagnosis and exits with a fatal error.

#### `perform_health_check()`

*   **Description**: Performs a health check to ensure the vLLM API server is responsive.
*   **Actions**:
    1.  Continuously sends requests to the `/health` endpoint.
    2.  Retries up to 10 times with a 10-second interval.
    3.  If the health check fails after all attempts, it logs the recent service logs and exits with a fatal error.

#### `validate_api_with_test_query()`

*   **Description**: Sends a test query to the vLLM API to validate that the embedding model is loaded and generating valid responses.
*   **Actions**:
    1.  Constructs a JSON payload for an embedding request.
    2.  Sends the request to the `/v1/embeddings` endpoint.
    3.  Checks the response for errors and validates that it contains a valid embedding data structure.
    4.  Logs a snippet of the response on success or exits with a fatal error on failure.

#### `display_connection_info()`

*   **Description**: Displays the final connection details for the vLLM embedding API server.
*   **Output**:
    *   IP Address and Port.
    *   The name of the loaded model.
    *   An example `curl` command for interacting with the embeddings API.

#### `main()`

*   **Description**: The main entry point of the script.
*   **Orchestration**: Calls the functions in the following order:
    1.  `parse_arguments`
    2.  `configure_systemd_service`
    3.  `manage_vllm_service`
    4.  `perform_health_check`
    5.  `validate_api_with_test_query`
    6.  `display_connection_info`

## 5. Dependencies

*   **`phoenix_hypervisor_common_utils.sh`**: Must be sourced for common utility functions (logging, error handling, etc.).
*   **`jq`**: Required for parsing the JSON configuration file.
*   **`curl`**: Used for performing health checks and API validation.
*   **`systemctl`**: Used within the container to manage the systemd service.
*   **`journalctl`**: Used to retrieve logs for failed services.

## 6. Error Handling

The script incorporates robust error handling:

*   **Strict Mode**: Uses `set -e` and `set -o pipefail` to ensure that the script exits immediately if any command fails.
*   **Logging**: Uses the `log_error` and `log_fatal` functions from the common utilities to provide clear error messages.
*   **Health Checks**: The `perform_health_check` function includes a retry mechanism and provides diagnostic logs upon failure.
*   **API Validation**: The `validate_api_with_test_query` function checks for errors and valid data structures in the API response.

## 7. Customization

The behavior of the script is customized through the `phoenix_lxc_configs.json` file. By modifying the vLLM-related parameters for CTID 951, you can change the model, command-line arguments, and other settings without altering the script itself.