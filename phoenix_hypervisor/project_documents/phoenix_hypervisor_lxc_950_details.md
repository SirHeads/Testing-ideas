# LXC Container 950 - `vllmQwen3Coder` - Details

## Overview

This document details the purpose, configuration, and setup process for LXC container `950`, named `vllmQwen3Coder`. This container serves as a specific application container within the Phoenix Hypervisor system, dedicated to serving the `lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-5bit` AI model using the vLLM framework. It is created by cloning the `vllm-base-snapshot` from container `920` (`BaseTemplateVLLM`) and then configured with the specific model and serving parameters. This is a final, functional application container intended for direct use, likely for integration with development tools like VS Code.

## Purpose

LXC container `950`'s primary purpose is to host and serve the `lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-5bit` AI model using the vLLM framework within a Docker container. It provides an accessible API endpoint for interacting with this specific model and leverages both host GPUs for optimal performance via tensor parallelism. This is a permanent, running service container for the Qwen3 Coder model, created by cloning from an existing vLLM-enabled template snapshot.

## Configuration (`phoenix_lxc_configs.json` - *Intended Final State*)

*   **CTID:** `950`
*   **Name:** `vllmQwen3Coder`
*   **Template Source:** `/fastData/shared-iso/template/cache/ubuntu-24.04-standard_24.04-2_amd64.tar.zst` (Note: While the template path is specified, this container is created by cloning).
*   **Resources:**
    *   **CPU Cores:** `8` (Allocated cores for the vLLM serving process)
    *   **Memory:** `40960` MB (40 GB RAM, allocated for the vLLM serving process and the 30B parameter model)
    *   **Storage Pool:** `lxc-disks`
    *   **Storage Size:** `100` GB (Root filesystem size, sufficient for the model file (~20GB) and dependencies)
*   **Network Configuration:**
    *   **Interface:** `eth0`
    *   **Bridge:** `vmbr0`
    *   **IP Address:** `10.0.0.150/24` (Permanent IP address for accessing the model's API endpoint. The script extracts only the IP address, e.g., `10.0.0.150`.)
    *   **Gateway:** `10.0.0.1`
    *   **MAC Address:** `52:54:00:67:89:B0`
*   **LXC Features:** `nesting=1,keyctl=1` (Essential `nesting=1` for Docker-in-LXC; `keyctl=1` included as potentially relevant for complex operations)
*   **Security & Privileges:**
    *   **Unprivileged:** `false` (Runs in privileged mode, necessary for full GPU access)
*   **GPU Assignment:** `0,1` (Configured to use both host GPUs)
*   **Portainer Role:** `agent` (This container could be managed by the Portainer Server)
*   **AI Framework Configuration:**
    *   **`vllm_model`:** `lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-5bit` (The specific HuggingFace model path to be served)
    *   **`vllm_tensor_parallel_size`:** `2` (Distributes the model across the two assigned GPUs)
*   **Cloning Metadata:**
    *   **`clone_from_template_ctid`:** `920` (Indicates this container is created by cloning from container `920`'s `vllm-base-snapshot`)

## Specific Setup Script (`phoenix_hypervisor_setup_950.sh`) Requirements

The `phoenix_hypervisor_setup_950.sh` script is responsible for the final configuration of the `vllmQwen3Coder` container *after* it has been cloned from `920`'s `vllm-base-snapshot` and booted. Its core responsibilities are:

*   **Model Server Deployment:**
    *   Ensures the container is fully booted and the inherited Docker environment (from `920`) is running.
    *   Ensures the Hugging Face token is available within the container. The script explicitly mounts the host's configured HF token file (`HF_TOKEN_FILE_PATH`) into the container at `/root/.cache/huggingface/token` as read-only.
    *   Pulls the official vLLM Docker image (e.g., `vllm/vllm-openai:latest`), if not already present from the `920` template.
    *   Runs the vLLM Docker container with the specific configuration for the Qwen3 model:
        *   Uses `--runtime nvidia` and `--gpus all` to enable GPU access.
        *   Maps the necessary port for the API (e.g., `-p 8000:8000`).
        *   Mounts the Hugging Face cache volume (`-v ~/.cache/huggingface:/root/.cache/huggingface`).
        *   Sets the container name (e.g., `--name vllm_qwen3_coder`).
        *   Configures restart policies (e.g., `--restart=always`).
        *   Uses `--ipc=host` as recommended.
        *   Passes the `vllm serve` command with the specific model and tensor parallelism:
            `vllm serve lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-5bit --tensor-parallel-size 2`
*   **Initial Configuration & Verification:**
    *   Waits for the model to load (this can take some time for a 30B model).
    *   Performs checks to ensure the vLLM container is running (`docker ps`).
    *   Verifies the API endpoint is responsive by sending a test request using `curl` to `http://10.0.0.150:8000/v1/chat/completions` with a simple prompt.
*   **Final State:**
    *   The script ensures the Qwen3 Coder vLLM service is up, running, and the model is loaded.
    *   It does *not* create a ZFS snapshot for templating, as this is a final application container.
    *   The container should be fully operational and ready to serve API requests upon script completion.

## Interaction with Phoenix Hypervisor System

*   **Creation:** `phoenix_establish_hypervisor.sh` will identify `950` as a standard container (not `is_template: true`) and see that `clone_from_template_ctid: "920"`. It will therefore call the cloning process (`phoenix_hypervisor_clone_lxc.sh`) to create `950` by cloning `920`'s `vllm-base-snapshot`.
*   **Setup:** After cloning and initial boot, `phoenix_establish_hypervisor.sh` will execute `phoenix_hypervisor_setup_950.sh`.
*   **Consumption:** External tools (like VS Code extensions) will connect to the model API endpoint at `http://10.0.0.150:8000`.
*   **Idempotency:** The setup script (`phoenix_hypervisor_setup_950.sh`) should be idempotent. If the vLLM container for this model is already running, it should skip the deployment steps and just log that the service is already configured.

## Exit Codes

The `phoenix_hypervisor_lxc_950.sh` script uses the following exit codes:

*   `0`: Success (vLLM Qwen3 Coder Server deployed/running, accessible).
*   `1`: General error.
*   `2`: Invalid input arguments.
*   `3`: Container 950 does not exist or is not accessible.
*   `4`: Docker is not functional inside container 950.
*   **5:** Failed to parse configuration files for required details.
*   **6:** vLLM Qwen3 Coder container deployment failed.
*   **7:** vLLM Qwen3 Coder verification (API accessibility) failed.

## Key Characteristics Summary

*   **Application Container:** A final, functional service for a specific AI model.
*   **Model Serving:** Runs the `lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-5bit` model using the vLLM framework in Docker.
*   **High-Performance:** Allocated significant resources (40GB RAM, 8 cores, 100GB storage) and utilizes both GPUs (`gpu_assignment: "0,1"`) with `tensor_parallel_size: 2`.
*   **Docker-in-LXC:** Relies on the `nesting=1` feature inherited from its base template (`920`).
*   **Privileged Mode:** Runs privileged (`unprivileged: false`) for GPU access.
*   **Static Network:** Uses a fixed IP (`10.0.0.150`) for reliable API access.
*   **GPU Enabled:** Fully utilizes both host GPUs for model inference.
*   **Cloned Origin:** Created by cloning the `vllm-base-snapshot` from `BaseTemplateVLLM` (`920`).