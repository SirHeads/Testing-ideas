# Unhealthy Container Remediation Plan

This document outlines the steps to resolve the unhealthy status of containers 951 (vllm-granite-embed) and 952 (qdrant-lxc).

## Container 951: vllm-granite-embed

**Issue:** The vLLM service is running, but its `/health` endpoint is unresponsive.

**Remediation Steps:**

1.  **Implement `/health` Endpoint:**
    *   A `/health` endpoint will be added to the vLLM service running in container 951.
    *   This endpoint will be designed to return a `200 OK` HTTP status code to indicate that the service is operational and ready to handle requests.
    *   The implementation will be done in the `embedding_server.py` script.

2.  **Update Health Check Script:**
    *   The script at `/usr/local/phoenix_hypervisor/bin/verify_container_health.sh` will be modified.
    *   The existing health check mechanism for container 951 will be updated to query the new `/health` endpoint.
    *   The script will interpret a `200 OK` response as a "healthy" status.

## Container 952: qdrant-lxc

**Issues:**
1.  Qdrant service is running but reports an "unrecognized filesystem" warning for its storage path.
2.  The `/health` endpoint is unresponsive.

**Remediation Steps:**

1.  **Resolve Filesystem Warning:**
    *   **Investigation:** The root cause of the "unrecognized filesystem" warning will be investigated. This will involve checking the current filesystem format of the storage path and Qdrant's storage requirements.
    *   **Resolution:** Based on the investigation, the storage path will be either reformatted to a supported filesystem (e.g., ext4) or the Qdrant data will be migrated to a new, correctly formatted storage volume. Data integrity will be ensured throughout this process.

2.  **Implement `/health` Endpoint:**
    *   A `/health` endpoint will be implemented for the Qdrant service.
    *   This endpoint will return a `200 OK` status if the Qdrant service is running correctly.
    *   Qdrant has a built-in health check endpoint (`/healthz`), so this step will likely involve ensuring it is accessible and correctly configured.

3.  **Update Health Check Script:**
    *   The `/usr/local/phoenix_hypervisor/bin/verify_container_health.sh` script will be updated for container 952.
    *   The health check will be modified to use the Qdrant `/healthz` endpoint to determine the container's health status.

By following these steps, we will address the root causes of the unhealthy statuses for both containers and ensure they report as healthy.