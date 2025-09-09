# VS Code Integration with LXC Containers and RooCode Extension

This document outlines the integration of VS Code with LXC containers 951, 952, 953, and the RooCode extension.

## LXC 951 (vLLM Embedding Service)

*   **Purpose:** Provides the embedding model for vectorization.
*   **Configuration:**
    *   **IP Address:** 10.0.0.151
    *   **Port:** 8000
    *   **Model:** `ibm-granite/granite-embedding-english-r2`
    *   **OpenAI Compatible API Endpoint:** `/v1/embeddings`
*   **VS Code Integration:**
    *   **Embedder Provider:** OpenAI Compatible
    *   **Base URL:** `http://10.0.0.153/v1` (Nginx Gateway)
    *   **API Key:** `fake-key` (required, but not validated)
    *   **Model:** `ibm-granite/granite-embedding-english-r2`
    *   **Model Dimension:** 768

## LXC 952 (Qdrant Vector Database)

*   **Purpose:** Stores and retrieves vectorized embeddings.
*   **Configuration:**
    *   **IP Address:** 10.0.0.152
    *   **Port:** 6333
*   **VS Code Integration:**
    *   **Qdrant URL:** `http://10.0.0.152:6333`
    *   **Qdrant API Key:** (Not Required)

## LXC 953 (Nginx API Gateway)

*   **Purpose:** Routes traffic to the vLLM embedding service.
*   **Configuration:**
    *   **IP Address:** 10.0.0.153
    *   **Listens on Port:** 80
    *   **Proxies `/v1/embeddings` to:** 10.0.0.151:8000

## RooCode Extension

*   **Purpose:** Provides the VS Code integration for RAG chunking, vectorization, and retrieval.
*   **Configuration:**
    *   **Embedder Provider:** OpenAI Compatible
    *   **Base URL:** `http://10.0.0.153/v1`
    *   **API Key:** `fake-key`
    *   **Model:** `ibm-granite/granite-embedding-english-r2`
    *   **Model Dimension:** 768
    *   **Qdrant URL:** `http://10.0.0.152:6333`
    *   **Qdrant API Key:** (Not Required)