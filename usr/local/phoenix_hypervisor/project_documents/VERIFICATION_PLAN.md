---
title: Container Verification Plan
summary: This document outlines the verification methods for each container to ensure a standardized and reliable process.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Verification
- Health Check
- LXC
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Container Verification Plan

This document outlines the verification methods for each container to ensure a standardized and reliable process.

## Container 951: vLLM API Server

*   **Service Management:** The vLLM API server is managed by a dynamically generated `systemd` service named `vllm_model_server`.
*   **Verification Method:**
    1.  **Health Check:** A `curl` request is sent to the `http://localhost:8000/health` endpoint. The script retries up to 10 times with a 10-second interval.
    2.  **API Validation:** A test query is sent to the `/v1/embeddings` endpoint to confirm the model is loaded and generating valid embeddings.
*   **Source:** [`phoenix_hypervisor_lxc_951.sh`](usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_951.sh)

## Container 953: Nginx Reverse Proxy

*   **Service Management:** The `nginx` service is managed by `systemd`.
*   **Verification Method:** The status of the `nginx` service is checked using the command `systemctl is-active --quiet nginx`.
*   **Source:** [`phoenix_hypervisor_lxc_953.sh`](usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_953.sh)

## Container 952: Qdrant Vector Database

*   **Service Management:** The Qdrant service is managed within a Docker container.
*   **Verification Method:** The health of the Qdrant service is checked by sending a `curl` request to `http://localhost:6333`. A successful request will return a JSON response containing the service title and version.