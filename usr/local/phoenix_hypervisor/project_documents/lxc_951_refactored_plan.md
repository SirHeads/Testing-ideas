---
title: 'LXC vLLM Deployment Refactoring Plan'
summary: This document outlines a plan to refactor the vLLM LXC deployment process by introducing a model_type field to the configuration.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- LXC Container
- vLLM
- Refactoring
- Deployment Plan
review_cadence: Annual
last_reviewed: 2025-09-23
---

# LXC vLLM Deployment Refactoring Plan

## 1. Objective

The objective of this plan is to refactor the vLLM LXC deployment process to make it more robust, maintainable, and scalable. This will be achieved by introducing a `vllm_model_type` field to the configuration, which will allow a single, unified application script to handle the deployment of different types of vLLM models (e.g., chat, embedding).

## 2. Proposed Changes

### 2.1. Configuration Schema Update

The `phoenix_lxc_configs.schema.json` file will be updated to include a new field, `vllm_model_type`.

*   **Field:** `vllm_model_type`
*   **Type:** `string`
*   **Enum:** `["chat", "embedding"]`
*   **Description:** Specifies the type of the vLLM model.

### 2.2. Configuration Update

The `phoenix_lxc_configs.json` file will be updated to include the new `vllm_model_type` field for all vLLM containers.

*   **For CTID 950:** `"vllm_model_type": "chat"`
*   **For CTID 951:** `"vllm_model_type": "embedding"`

### 2.3. Unified Application Script

A single, unified application script, `phoenix_hypervisor_lxc_vllm.sh`, will be created to replace the individual scripts for each vLLM container (e.g., `phoenix_hypervisor_lxc_950.sh`, `phoenix_hypervisor_lxc_951.sh`).

This new script will:

1.  Read the `vllm_model_type` from the configuration file.
2.  Dynamically construct the API validation query based on the model type.
3.  Send the query to the appropriate API endpoint (`/v1/chat/completions` for chat models, `/v1/embeddings` for embedding models).
4.  Validate the response based on the expected format for the model type.

## 3. Implementation Steps

### Step 1: Update JSON Schema

*   [ ] Modify `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json` to add the `vllm_model_type` field.

### Step 2: Update LXC Configuration

*   [ ] Modify `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json` to add the `vllm_model_type` field to the configurations for CTIDs `950` and `951`.

### Step 3: Create Unified Application Script

*   [ ] Create a new script, `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_vllm.sh`.
*   [ ] Copy the contents of `phoenix_hypervisor_lxc_950.sh` into the new script as a starting point.
*   [ ] Modify the `validate_api_with_test_query` function to read the `vllm_model_type` and perform the appropriate validation.

### Step 4: Update LXC Configuration to Use New Script

*   [ ] Modify `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json` to update the `application_script` field for CTIDs `950` and `951` to point to the new unified script.

### Step 5: Remove Old Scripts

*   [ ] Remove the old application scripts (`phoenix_hypervisor_lxc_950.sh` and `phoenix_hypervisor_lxc_951.sh`).

## 4. Benefits of this Approach

*   **Single Source of Truth:** The `vllm_model_type` field provides a single source of truth for the model type, making the configuration more explicit and easier to understand.
*   **Reduced Code Duplication:** A single, unified script eliminates the need for separate scripts for each vLLM container, reducing code duplication and making the system easier to maintain.
*   **Improved Scalability:** This approach makes it easy to add support for new model types in the future by simply adding a new value to the `vllm_model_type` enum and updating the validation logic in the unified script.

This plan is now ready for your review. Please let me know if you are pleased with this direction, or if you would like to make any changes.