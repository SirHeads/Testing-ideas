---
title: 'LXC 951: vllm-granite-embed - Deployment Plan'
summary: This document outlines the plan to create and configure LXC container 951 to host the vllm-granite-embed embedding model.
document_type: Implementation Plan
status: Approved
version: '1.1'
author: Roo
owner: Thinkheads.AI
tags:
  - lxc
  - vllm
  - deployment
review_cadence: Annual
last_reviewed: '2025-09-30'
---

# LXC 951 Deployment Plan

## 1. Objective

The objective of this plan is to deploy a new vLLM instance in LXC container `951` to serve the `ibm-granite/granite-embedding-english-r2` model. The deployment will be based on the existing process used for LXC container `950`, with necessary modifications to support an embedding model.

## 2. High-Level Plan

The deployment will follow these steps:

1.  **Configuration:** Update `phoenix_lxc_configs.json` with the specific parameters for container `951`.
2.  **Script Adaptation:** Create the `phoenix_hypervisor_lxc_951.sh` script by adapting `phoenix_hypervisor_lxc_950.sh`. The key change will be in the API validation function.
3.  **Execution:** Use the `phoenix` CLI to create, configure, and launch the container.
4.  **Validation:** The new script will perform health checks and a final API validation tailored for the vLLM embeddings endpoint.

## 3. Key Differences from LXC 950

The primary difference between the setup for `950` and `951` is the model type and the corresponding API endpoint for validation.

*   **LXC 950 (Chat Model):** Validates against the `/v1/chat/completions` endpoint.
*   **LXC 951 (Embedding Model):** Must validate against the `/v1/embeddings` endpoint.

## 4. Implementation Steps

### Step 1: Update `phoenix_lxc_configs.json`

Ensure the configuration for CTID `951` is present and correct in `phoenix_lxc_configs.json`. This configuration should specify the correct model, resource allocation, and the new application script.

```json
"951": {
    "name": "vllm-granite-embed",
    "memory_mb": 72000,
    "cores": 12,
    "storage_pool": "quickOS-lxc-disks",
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
    "vllm_served_model_name": "ibm-granite/granite-embedding-english-r2",
    "vllm_tensor_parallel_size": 2,
    "vllm_gpu_memory_utilization": 0.85,
    "vllm_max_model_len": 8192
}
```

### Step 2: Create `phoenix_hypervisor_lxc_951.sh`

Create the new script by copying `phoenix_hypervisor_lxc_950.sh`. The following modifications are required:

*   **Modify `validate_api_with_test_query` function:**
    *   Change the `api_url` to `http://localhost:8000/v1/embeddings`.
    *   Update the `json_payload` to the format expected by the embeddings endpoint (e.g., `{"model": "model_name", "input": "test string"}`).
    *   Update the response validation logic to check for a valid embedding vector in the API response.

The existing `phoenix_hypervisor_lxc_951.sh` script already implements these changes correctly.

### Step 3: Execute the CLI

Run the `phoenix` CLI, specifying CTID `951`.

```bash
/usr/local/phoenix_hypervisor/bin/phoenix create 951
```

The CLI will handle the container creation, feature installation, and execution of the new application script.

## 5. Validation

The `phoenix_hypervisor_lxc_951.sh` script will automatically perform the following validation steps:

1.  **Health Check:** Ensure the vLLM server is responsive.
2.  **API Validation:** Send a test query to the `/v1/embeddings` endpoint and verify the response.

This plan is now ready for your review. Please let me know if you are pleased with this direction, or if you would like to make any changes.