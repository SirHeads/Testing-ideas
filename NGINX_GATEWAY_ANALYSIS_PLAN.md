# NGINX Gateway Analysis and Testing Plan

This document outlines the expected functionality of the services exposed through the nginx gateway at `10.0.0.153`. It serves as a basis for a diagnostic and testing plan.

## NGINX Gateway IP Address

The nginx gateway container (`Nginx-VscodeRag`) is configured with the following IP address:

*   **IP Address:** `10.0.0.153`

## Service Definitions

### 1. qdrant

*   **Local Endpoint:** `http://10.0.0.153/qdrant/`
*   **Key Functionalities:** The qdrant service should be accessible and report a healthy status. The primary functionality is to provide a vector database for AI applications.
*   **Example `curl` command:** This command checks the health of the qdrant service.
    ```bash
    curl -X GET http://10.0.0.153/qdrant/healthz
    ```
    **Expected Output:** A successful response indicating the service is healthy.

### 2. vllm chat (granite)

*   **Local Endpoint:** `http://10.0.0.153/v1/chat/completions`
*   **Key Functionalities:** The vllm chat service should be able to receive a prompt and return a text completion. This service is used for generative AI tasks.
*   **Example `curl` command:** This command sends a chat completion request to the `granite` model.
    ```bash
    curl -X POST http://10.0.0.153/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
      "model": "granite-3.3-8b-instruct",
      "messages": [
        {
          "role": "user",
          "content": "Hello! What is your name?"
        }
      ]
    }'
    ```
    **Expected Output:** A JSON response containing a text completion from the model.

### 3. vllm embedding

*   **Local Endpoint:** `http://10.0.0.153/v1/embeddings`
*   **Key Functionalities:** The vllm embedding service should be able to receive text and return a vector embedding. This is used for tasks like semantic search and clustering.
*   **Example `curl` command:** This command sends a request to get an embedding for the input text.
    ```bash
    curl -X POST http://10.0.0.153/v1/embeddings \
    -H "Content-Type: application/json" \
    -d '{
      "model": "ibm-granite/granite-embedding-english-r2",
      "input": "Hello, world!"
    }'
    ```
    **Expected Output:** A JSON response containing the vector embedding for the input text.

### 4. n8n

*   **Local Endpoint:** `http://10.0.0.153/n8n/`
*   **Key Functionalities:** The n8n service should be accessible and display the n8n workflow automation tool's web interface.
*   **Example `curl` command:** This command will access the n8n web interface.
    ```bash
    curl -L http://10.0.0.153/n8n/
    ```
    **Expected Output:** The HTML content of the n8n login page. The `-L` flag is used to follow redirects.

### 5. Portainer

*   **Local Endpoint:** Not accessible via the gateway IP address.
*   **Key Functionalities:** The Portainer service is configured to be accessed via the hostname `portainer.phoenix.local` and is not directly exposed through the gateway's IP address. Therefore, it cannot be tested from the Proxmox host using the gateway IP.
