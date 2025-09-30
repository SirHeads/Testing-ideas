---
title: 'Feature: Python API Service Environment'
summary: The `python_api_service` feature establishes a foundational Python environment in a container by installing Python 3, pip, and venv.
document_type: "Feature Summary"
status: "Approved"
version: "1.0.0"
author: "Phoenix Hypervisor Team"
owner: "Developer"
tags:
  - "Python"
  - "API"
  - "Development Environment"
  - "pip"
  - "venv"
review_cadence: "Annual"
last_reviewed: "2025-09-30"
---

The `python_api_service` feature is a foundational script that prepares a container for running Python-based applications. It installs the core components required for a modern Python development workflow.

## Key Actions

1.  **Package Installation:** The script installs the following packages using `apt-get`:
    *   `python3`: The Python 3 interpreter.
    *   `python3-pip`: The standard package installer for Python.
    *   `python3-venv`: The module for creating isolated Python virtual environments.

2.  **Verification:** After installation, the script verifies that the `python3` and `pip3` commands are available in the container's path.

## Idempotency

The script is idempotent. It checks if both `python3` and `pip3` are already installed. If they are, the installation process is skipped.

## Usage

This feature serves as a prerequisite for any other feature that requires a Python runtime, such as the `vllm` feature. It should be listed before any Python-dependent features in the `features` array of the container's configuration.