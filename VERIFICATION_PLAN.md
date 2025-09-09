# Verification Plan

This document outlines the steps to verify the corrected Nginx configuration and ensure the overall stability of the RAG pipeline.

## 1. Verify Nginx Configuration

**Objective:** Ensure the Nginx API gateway correctly routes traffic to the vLLM embedding service.

**Steps:**

1.  **Redeploy LXC Container 953:** Use the `phoenix_orchestrator.sh` script to rebuild the `api-gateway-lxc` container.
    ```bash
    /usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh 953
    ```
2.  **Send a Test Request:** Use `curl` to send a request to the `/v1/embeddings` endpoint through the Nginx gateway.

    ```bash
    curl -X POST http://10.0.0.153/v1/embeddings \
    -H "Content-Type: application/json" \
    -d '{"model": "ibm-granite/granite-embedding-english-r2", "input": "This is a test."}'
    ```

**Expected Outcome:** The command should return a successful JSON response containing the embedding vector.

## 2. Verify Direct Access to Qdrant

**Objective:** Confirm that the Qdrant vector database is still accessible directly.

**Steps:**

1.  **Send a Test Request:** Use `curl` to check the health of the Qdrant service.
    ```bash
    curl http://10.0.0.152:6333/health
    ```

**Expected Outcome:** The command should return a successful response from the Qdrant health check endpoint.

## 3. End-to-End RAG Pipeline Test

**Objective:** Perform a full end-to-end test of the RAG pipeline.

**Steps:**

1.  **Chunk and Vectorize a Document:** Use the appropriate client to send a document to be chunked and vectorized.
2.  **Perform a Retrieval:** Query the system with a relevant question to retrieve the correct chunks.

**Expected Outcome:** The system should successfully retrieve the relevant chunks from the vectorized document.