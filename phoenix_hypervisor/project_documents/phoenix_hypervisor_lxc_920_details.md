# LXC Container 920 - `BaseTemplateVLLM` - Details

## Overview

This document details the purpose, configuration, and setup process for LXC container `920`, named `BaseTemplateVLLM`. This container serves as a specialized template level in the Phoenix Hypervisor's snapshot-based hierarchy, integrating GPU support and the vLLM serving framework. It is created by cloning the `gpu-snapshot` from container `901` (`BaseTemplateGPU`) and then configured with the vLLM framework and its dependencies. It is never intended to be used as a final, running application container. Templates requiring GPU and vLLM support (e.g., `950`) and standard application containers needing this specific stack will be created by cloning the `vllm-base-snapshot` taken from this template.

## Purpose

LXC container `920`'s primary purpose is to provide a standardized Ubuntu 24.04 environment with direct GPU access and the vLLM serving framework pre-installed and configured directly (not in Docker). This allows containers to access GPUs and easily deploy vLLM-based models. It serves as the foundational layer for all other templates and containers that require this specific AI serving stack. It is exclusively used for cloning; a ZFS snapshot (`vllm-base-snapshot`) is created after its initial setup for other vLLM-dependent containers/templates to clone from.

## Configuration (`phoenix_lxc_configs.json`)

*   **CTID:** `920`
*   **Name:** `BaseTemplateVLLM`
*   **Template Source:** `/fastData/shared-iso/template/cache/ubuntu-24.04-standard_24.04-2_amd64.tar.zst` (Note: While the template path is specified, this container is created by cloning).
*   **Resources:**
    *   **CPU Cores:** `4` (Slightly higher allocation than lower templates, suitable for framework setup)
    *   **Memory:** `4096` MB (4 GB RAM, sufficient for base OS, Docker, GPU tools, and vLLM setup)
    *   **Storage Pool:** `lxc-disks`
    *   **Storage Size:** `64` GB (Root filesystem size)
*   **Network Configuration:**
    *   **Interface:** `eth0`
    *   **Bridge:** `vmbr0`
    *   **IP Address (Placeholder):** `10.0.0.220/24` (This IP is for template consistency and will be changed upon cloning. Using `.220` avoids overlap with common application IPs)
    *   **Gateway:** `10.0.0.1`
    *   **MAC Address (Placeholder):** `52:54:00:AA:BB:D1` (Will be changed upon cloning)
*   **LXC Features:** `` (No special features enabled at this level)
*   **Security & Privileges:**
    *   **Unprivileged:** `true` (Runs in unprivileged mode for enhanced security)
*   **GPU Assignment:** `0,1` (Configured to have direct access to both host GPUs)
*   **Template Metadata (for Snapshot Hierarchy):**
    *   **`is_template`:** `true` (Identifies this configuration as a template)
    *   **`template_snapshot_name`:** `vllm-base-snapshot` (Name of the ZFS snapshot this template will produce)
    *   **`clone_from_template_ctid`:** `901` (Indicates this template is created by cloning from container `901`)
*   **AI Framework Configuration (for Reference/Clones):**
    *   **`vllm_model`:** `/models/test-model` (A placeholder/test path. Actual models are configured in containers cloned from this template's snapshot).
    *   **`vllm_tensor_parallel_size`:** `1` (A placeholder value. Tensor parallelism is configured in containers cloned from this template's snapshot).

## Specific Setup Script (`phoenix_hypervisor/bin/phoenix_hypervisor_lxc_920.sh`) Requirements

The `phoenix_hypervisor/bin/phoenix_hypervisor_lxc_920.sh` script is responsible for the final configuration of the `BaseTemplateVLLM` container *after* it has been cloned from `901`'s `gpu-snapshot` and booted. Its core responsibilities are:

### Dependencies
*   `jq`: For parsing JSON output from the vLLM API test.
*   `python3-venv`: For creating Python virtual environments.
*   `pip`: Python package installer.

*   **Verify Inherited Stack:**
    *   Ensures the container is fully booted.
    *   Confirms that direct GPU access (inherited from `901`) is correctly configured and running. This might involve checking `nvidia-smi`.
*   **vLLM Framework Setup & Verification:**
    *   Installs `vLLM` directly into the container's Python environment.
    *   Runs a test vLLM server directly to verify the environment:
        *   Uses a small, quick-to-load model suitable for testing (e.g., `Qwen/Qwen2.5-Coder-0.5B-Instruct-GPTQ-Int8`).
        *   Launches the vLLM server on a test port (e.g., `8000`).
    *   Waits for the test model to load (up to 300 seconds).
    *   Performs a basic API test using `curl` or similar to send a request to the test server's endpoint (e.g., `http://localhost:8000/v1/chat/completions`) and verifies a response. The script attempts to stop the test server even if the API test fails.
    *   Stops the test server.
*   **Finalize and Snapshot Creation:**
    *   Once the vLLM environment is verified, the script's final step is to shut down the container.
    *   It then executes `pct snapshot create 920 vllm-base-snapshot` to create the ZFS snapshot that forms the basis for the vLLM template hierarchy.
    *   Finally, it restarts the container.

## Interaction with Phoenix Hypervisor System

*   **Creation:** `phoenix_establish_hypervisor.sh` will identify `920` as a template (`is_template: true`) and see that `clone_from_template_ctid: "901"`. It will therefore call the cloning process (`phoenix_hypervisor_clone_lxc.sh`) to create `920` by cloning `901`'s `gpu-snapshot`.
*   **Setup:** After cloning and initial boot, `phoenix_establish_hypervisor.sh` will execute `phoenix_hypervisor_lxc_920.sh`.
*   **Consumption:** Other templates (e.g., `950` - `vllmQwen3Coder`) or standard containers needing the Docker+GPU+vLLM stack can have `clone_from_template_ctid: "920"` in their configuration. The orchestrator will use this to determine they should be created by cloning `920`'s `vllm-base-snapshot`.
*   **Idempotency:** The setup script (`phoenix_hypervisor_lxc_920.sh`) must be idempotent. If `vllm-base-snapshot` already exists, it should skip the setup steps and potentially just log that the template is already prepared.

## Key Characteristics Summary

*   **vLLM Base:** Provides the core OS, direct GPU access, and the vLLM serving framework (installed directly).
*   **Unprivileged Mode:** Runs unprivileged (`unprivileged: true`) for enhanced security.
*   **Generic Network:** Uses placeholder IP/MAC (`.220`) which are changed on clone to avoid conflicts.
*   **Dual GPU Access:** Configured for direct access to GPUs 0 and 1.
*   **Template Only:** Never used as a final application container.
*   **Snapshot Source:** The origin of the `vllm-base-snapshot` ZFS snapshot for containers requiring the Docker+GPU+vLLM stack.