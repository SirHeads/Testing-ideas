---
title: 'LXC Container 951: vllm-granite-embed - Architecture and Implementation Plan'
summary: This document outlines the architectural plan for the creation and configuration
  of LXC container `951`, now named `vllm-granite-embed`. This container will host
  a vLLM instance serving the `ibm-granite/granite-embedding-english-r2` model. Its
  setup will be based on a clone of container `920` and will adapt the configuration
  of container `950` to support an embedding model.
document_type: Strategy | Technical | Business Case | Report
status: Draft | In Review | Approved | Archived
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Team/Individual Name
tags:
- LXC Container
- vLLM
- granite-embed
- Architecture
- Implementation Plan
- Phoenix Hypervisor
- AI
- Machine Learning
- Embeddings
review_cadence: Annual | Quarterly | Monthly | None
last_reviewed: YYYY-MM-DD
---
This document outlines the architectural plan for the creation and configuration of LXC container `951`, now named `vllm-granite-embed`. This container will host a vLLM instance serving the `ibm-granite/granite-embedding-english-r2` model. Its setup will be based on a clone of container `920` and will adapt the configuration of container `950` to support an embedding model.

## 2. High-Level Plan

The deployment will follow these stages:

1.  **Configuration:** Update `phoenix_lxc_configs.json` with the specific parameters for container `951`, including the new name and model.
2.  **Script Creation:** Create a new application runner script, `phoenix_hypervisor_lxc_951.sh`, by adapting the existing script for container `950`. This adaptation is critical and will involve changing the API validation logic.
3.  **Execution:** The `phoenix_orchestrator.sh` script will use the updated configuration to create, configure, and launch the container.
4.  **Validation:** The new script will perform health checks and a final API validation specifically tailored for the vLLM embeddings endpoint to ensure the container is fully operational.

## 3. Requirements

### 3.1. Functional Requirements

- The container must run a vLLM API server.
- The server must host the `ibm-granite/granite-embedding-english-r2` model.
- The API must be accessible on the network at `http://10.0.0.151:8000`.
- The API must expose an OpenAI-compatible `/v1/embeddings` endpoint.
- The service must be managed by `systemd` to ensure it is persistent and restarts on failure.

### 3.2. Non-Functional Requirements

- The container setup must be automated and repeatable.
- The configuration should be centralized in `phoenix_lxc_configs.json`.
- The container must be based on a clone of container `920` (`BaseTemplateVLLM`).
- The resource allocation (CPU, memory, GPU) should be consistent with similar vLLM containers.

## 4. Technical Specifications

### 4.1. LXC Configuration (`phoenix_lxc_configs.json`)

The following parameters will be added to the configuration for CTID `951`:

```json
"951": {
    "name": "vllm-granite-embed",
    "memory_mb": 72000,
    "cores": 12,
    "storage_pool": "lxc-disks",
    "storage_size_gb": 128,
    "network_config": {
        "name": "eth0",
        "bridge": "vmbr0",
        "ip": "10.0.0.151/24",
        "gw": "10.0.0.1"
    },
    "mac_address": "52:54:00:67:89:B1",
    "gpu_assignment": "0,1",
    "unprivileged": true,
    "portainer_role": "none",
    "clone_from_ctid": "920",
    "features": [
        "vllm"
    ],
    "application_script": "phoenix_hypervisor_lxc_951.sh",
    "vllm_model": "ibm-granite/granite-embedding-english-r2",
    "vllm_tensor_parallel_size": 2,
    "vllm_gpu_memory_utilization": 0.85,
    "vllm_max_model_len": 8192
}
```

### 4.2. Resource Allocation

-   **CPU:** 12 cores
-   **Memory:** 72000 MB
-   **Storage:** 128 GB
-   **GPU:** Passthrough of GPUs `0` and `1`.

## 5. Scripting Needs

### 5.1. `phoenix_hypervisor_lxc_951.sh`

A new script, `phoenix_hypervisor_lxc_951.sh`, will be created in `phoenix_hypervisor/bin/`. This script will be **adapted** from `phoenix_hypervisor_lxc_950.sh`.

**Crucial Modifications Required:**

-   The `validate_api_with_test_query` function must be rewritten. Instead of querying the `/v1/chat/completions` endpoint, it must query the `/v1/embeddings` endpoint.
-   The JSON payload for the validation query must be changed to the format expected by the embeddings endpoint (e.g., `{"model": "model_name", "input": "test string"}`).
-   The logic for verifying a successful response must be updated to check for a valid embedding vector in the API response, rather than a chat message.

### 5.2. Feature Scripts

No new "feature" scripts are anticipated. The existing `vllm` feature script, which handles the installation of vLLM and its dependencies, is sufficient. The optional `flash_attn` dependency can be added to the `vllm` feature script for improved performance.

## 6. Workflow Diagram

```mermaid
graph TD
    A[Start] --> B{Update phoenix_lxc_configs.json with granite model};
    B --> C{Create phoenix_hypervisor_lxc_951.sh};
    C --> D{Modify script to validate /v1/embeddings endpoint};
    D --> E{Run phoenix_orchestrator.sh for CTID 951};
    E --> F{Container Cloned from 920};
    F --> G{Features Installed};
    G --> H{Application Script Executed};
    H --> I{vLLM Service Started};
    I --> J{Health Check & Embeddings API Validation};
    J --> K[End];
