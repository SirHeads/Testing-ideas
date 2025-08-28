# `phoenix_lxc_configs.json` (and `phoenix_lxc_configs.schema.json`) - Summary

## Overview

This document summarizes the purpose, structure, and role of the `phoenix_lxc_configs.json` file and its associated JSON Schema (`phoenix_lxc_configs.schema.json`) within the Phoenix Hypervisor system. This pair defines *what* LXC containers to create, their specific configurations, and provides a mechanism to ensure the configuration data is valid.

## Purpose

The `phoenix_lxc_configs.json` file is the core definition file for all LXC containers managed by the Phoenix Hypervisor. It contains a collection of individual container configurations, each specifying the resources, network settings, features (like GPU access, Docker nesting), and specific roles (like Portainer server/agent) for that container. The `phoenix_lxc_configs.schema.json` file provides a formal definition of the expected structure and data types within `phoenix_lxc_configs.json`, enabling automated validation to prevent configuration errors.

## Key Responsibilities

1.  **Define Container Blueprints:**
    *   Contains a map/object where each key is a Container ID (CTID) and the value is the detailed configuration object for that container.
    *   Specifies per-container settings like name, memory, CPU cores, storage details, network configuration, LXC features, and security settings.

2.  **Specify Specialized Configurations:**
    *   Defines GPU assignment for containers (`gpu_assignment`: "none", "0", "1", "0,1").
    *   Defines the role within the Portainer management system (`portainer_role`: "server", "agent", "none").
    *   Includes placeholders for AI-specific configurations (e.g., `vllm_model`, `vllm_tensor_parallel_size`).

3.  **Provide Global NVIDIA Settings:**
    *   Defines the expected NVIDIA driver version (`nvidia_driver_version`) on the host.
    *   Defines the URL for the NVIDIA CUDA APT repository (`nvidia_repo_url`).
    *   Defines the URL for the NVIDIA Driver `.run` file (`nvidia_runfile_url`).

4.  **Enable Validation:**
    *   The `phoenix_lxc_configs.schema.json` file allows tools (like `ajv-cli`) and scripts to validate that `phoenix_lxc_configs.json` adheres to the expected structure and data types before it's used to create containers, preventing runtime errors due to misconfiguration.

## Structure & Content (`phoenix_lxc_configs.json`)

The file is a JSON object with the following top-level keys:

*   `$schema`: URI pointing to `phoenix_lxc_configs.schema.json`.
*   `nvidia_driver_version`: String representing the host's NVIDIA driver version.
*   `nvidia_repo_url`: String (URI) for the NVIDIA CUDA APT repository.
*   `nvidia_runfile_url`: String (URI) for the NVIDIA Driver `.run` file.
*   `lxc_configs`: An object where keys are string representations of CTIDs (e.g., "901") and values are individual container configuration objects.
    *   **Per-Container Configuration Object:**
        *   `name`: Human-readable container name.
        *   `memory_mb`: RAM allocation in MB.
        *   `cores`: Number of CPU cores.
        *   `template`: Path to the LXC template tarball.
        *   `storage_pool`: Name of the Proxmox storage pool.
        *   `storage_size_gb`: Size of the root filesystem in GB.
        *   `network_config`: Object containing `name`, `bridge`, `ip` (CIDR), `gw`.
        *   `features`: String of LXC features (e.g., "nesting=1").
        *   `static_ip`: (Potentially redundant) Static IP in CIDR notation.
        *   `mac_address`: MAC address for the container's interface.
        *   `gpu_assignment`: String specifying which GPUs to pass through.
        *   `portainer_role`: String defining the Portainer role.
        *   `unprivileged`: Boolean for unprivileged mode.
        *   `vllm_model`: (Optional) Path to a vLLM model.
        *   `vllm_tensor_parallel_size`: (Optional) Tensor parallelism setting for vLLM.

## Structure & Content (`phoenix_lxc_configs.schema.json`)

The schema is a JSON Schema Draft 07 document that defines:

*   The required top-level keys (`$schema`, `nvidia_driver_version`, `nvidia_repo_url`, `nvidia_runfile_url`, `lxc_configs`).
*   The structure and data types for `nvidia_driver_version`, `nvidia_repo_url`, and `nvidia_runfile_url`.
*   The structure of the `lxc_configs` object, including:
    *   Keys must be strings matching a specific pattern (CTID numbers).
    *   The structure and constraints for each individual container configuration object (required fields, data types, value patterns like IP address format, `gpu_assignment` format, `portainer_role` enum values).
    *   Restrictions on additional properties to enforce schema adherence.

## Interaction with Other Components

*   **Consumed By:** `phoenix_establish_hypervisor.sh` (and its sub-scripts via re-parsing or arguments) to determine which containers to create and how to configure them.
*   **Validated By:** `phoenix_establish_hypervisor.sh` uses `phoenix_lxc_configs.schema.json` (via a tool like `ajv-cli`) to validate `phoenix_lxc_configs.json` before processing.
*   **Input Source:** This file is loaded by the orchestrator based on a path defined in `phoenix_hypervisor_config.json` or hardcoded.

## Output & Error Handling

*   **Output:** These files themselves produce no output; they are static configuration inputs.
*   **Error Handling:** The consuming script (`phoenix_establish_hypervisor.sh`) is responsible for validating `phoenix_lxc_configs.json` against `phoenix_lxc_configs.schema.json`. If validation fails, the script should log an error detailing the problem and exit.