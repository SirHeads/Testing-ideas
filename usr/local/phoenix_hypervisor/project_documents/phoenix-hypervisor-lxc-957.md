---
title: Script Guide - phoenix_hypervisor_lxc_957.sh
summary: This document provides a comprehensive guide to the phoenix_hypervisor_lxc_957.sh script, detailing its purpose, usage, and functionality for setting up the llamacppBase container.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Script Guide
- llama.cpp
- LXC
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Script Guide: `phoenix_hypervisor_lxc_957.sh`

## 1. Introduction

This guide provides detailed documentation for the `phoenix_hypervisor_lxc_957.sh` script. This script is designed to automate the complete setup of the `llamacppBase` LXC container (ID 957), which serves as a foundational environment for running `llama.cpp`.

## 2. Purpose

The primary purpose of this script is to provide a standardized and automated method for installing and compiling `llama.cpp` with GPU support. It ensures that all necessary dependencies are installed, the source code is cloned and compiled correctly, and the environment is verified to be functional.

## 3. Usage

The script is intended to be executed as a setup utility within the `llamacppBase` LXC container. It does not require any command-line arguments.

### Syntax

```bash
./phoenix_hypervisor_lxc_957.sh
```

## 4. Script Breakdown

### Configuration Variables

The script uses the following variables to define its operational parameters:

*   `LOG_FILE`: The path to the log file where all script output is stored. Default: `"/var/log/phoenix_hypervisor_lxc_957.log"`
*   `LLAMA_CPP_DIR`: The directory where the `llama.cpp` repository will be cloned. Default: `"/opt/llama.cpp"`
*   `IP_ADDRESS`: The static IP address assigned to the container, used for informational purposes. Default: `"10.0.0.157"`
*   `PORT`: The default port for the `llama.cpp` server. Default: `"8080"`

### Functions

*   **`log_message()`**:
    *   Logs a timestamped message to both standard output and the `LOG_FILE`.

*   **`command_exists()`**:
    *   Checks if a given command is available in the system's `PATH`.

*   **`install_dependencies()`**:
    *   Updates the package list and installs `build-essential`, `cmake`, and `git`.

*   **`clone_or_update_llama_cpp()`**:
    *   Clones the `llama.cpp` repository from GitHub into `LLAMA_CPP_DIR`.
    *   If the directory already exists, it pulls the latest changes.

*   **`compile_llama_cpp()`**:
    *   Compiles the `llama.cpp` source code.
    *   It checks for the `nvcc` compiler and, if present, compiles with cuBLAS support for NVIDIA GPUs.
    *   If `nvcc` is not found, it compiles without GPU support and logs a warning.

*   **`perform_health_checks()`**:
    *   Verifies that the `llama-cli` and `server` binaries were created successfully.
    *   If `nvidia-smi` is available, it logs the GPU status.

*   **`display_info()`**:
    *   Prints a summary message upon successful completion, indicating the location of the binaries and the default server URL.

*   **`main()`**:
    *   The main entry point for the script, orchestrating the execution of all setup functions in the correct order.

## 5. Dependencies

*   **System Packages**: `build-essential`, `cmake`, `git`.
*   **NVIDIA CUDA Toolkit**: Required for GPU-accelerated compilation (cuBLAS). The script checks for `nvcc` to confirm its presence. It is expected that the CUDA toolkit is installed and configured by a preceding feature script.

## 6. Error Handling

The script is configured with `set -euo pipefail`, which causes it to exit immediately if any command fails, an unset variable is referenced, or a command in a pipeline fails. Key functions include explicit error checks and will terminate the script with a descriptive error message if a critical step (e.g., dependency installation, compilation) fails.

## 7. Customization

This script is designed to be self-contained. To change its behavior, such as the installation directory or default port, the configuration variables at the top of the script must be modified directly.