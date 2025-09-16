# System Architecture Overview: Shared Storage and NGINX Gateway

This document provides a high-level overview of the shared storage strategy and the NGINX gateway configuration for the Phoenix Hypervisor system.

## Shared Storage Summary

The shared storage strategy is designed to provide centralized, persistent storage for various services running in LXC containers. This approach simplifies data management, reduces data duplication, and ensures data availability across container restarts and migrations. The configuration is driven by `phoenix_hypervisor_config.json`, which defines the shared volumes, and `phoenix_lxc_configs.json`, which defines the LXC containers that use them.

```mermaid
graph TD
    subgraph "Configuration Files"
        A["phoenix_hypervisor_config.json<br/>(defines shared_volumes)"]
        B["phoenix_lxc_configs.json<br/>(defines LXC containers)"]
    end

    subgraph "Host System Storage"
        C["/mnt/pve/quickOS/shared-prod-data"]
        D["/mnt/pve/fastData/shared-prod-data"]
        E["/mnt/pve/fastData/shared-bulk-data"]
        F["/usr/local/phoenix_hypervisor/etc/nginx/sites-available"]
    end

    subgraph "LXC Containers"
        LXC953["LXC 953 - NGINX Gateway"]
        LXC910["LXC 910 - Portainer"]
        LXC952["LXC 952 - Qdrant"]
        LXC954["LXC 954 - n8n"]
        LXC955["LXC 955 - Ollama"]
        LXC957["LXC 957 - Llama.cpp"]
        LXC950["LXC 950 - vLLM"]
        LXC951["LXC 951 - vLLM"]
    end

    A -- "defines host_path" --> C
    A -- "defines host_path" --> D
    A -- "defines host_path" --> E
    A -- "defines host_path" --> F

    B -- "defines LXC 953" --> LXC953
    B -- "defines LXC 910" --> LXC910
    B -- "defines LXC 952" --> LXC952
    B -- "defines LXC 954" --> LXC954
    B -- "defines LXC 955" --> LXC955
    B -- "defines LXC 957" --> LXC957
    B -- "defines LXC 950" --> LXC950
    B -- "defines LXC 951" --> LXC951

    C -- "/ssl" --> LXC953
    C -- "/ssl" --> LXC910
    C -- "/portainer/data" --> LXC910
    C -- "/logs/nginx" --> LXC953
    C -- "/n8n" --> LXC954
    D -- "/qdrant" --> LXC952
    E -- "/ollama_models" --> LXC955
    E -- "/llamacpp_models" --> LXC957
    E -- "/vllm_models" --> LXC950
    E -- "/vllm_models" --> LXC951
    F -- "/sites-available" --> LXC953
```

The following shared volumes are configured:

*   **`ssl_certs`**:
    *   **Purpose**: Provides a centralized location for SSL certificates.
    *   **LXCs**: `953` (NGINX Gateway), `910` (Portainer)
    *   **Use Case**: The `ssl_certs` volume ensures that all services requiring SSL encryption can access the same certificates, simplifying certificate management and renewal.

*   **`portainer_data`**:
    *   **Purpose**: Stores persistent data for the Portainer container management UI.
    *   **LXCs**: `910` (Portainer)
    *   **Use Case**: This volume ensures that Portainer's configuration, user data, and container information are preserved across restarts.

*   **`nginx_sites`**:
    *   **Purpose**: Stores the NGINX site configurations.
    *   **LXCs**: `953` (NGINX Gateway)
    *   **Use Case**: This volume allows for easy management and updates of NGINX configurations from the host system without needing to access the container directly.

*   **`nginx_logs`**:
    *   **Purpose**: Centralizes NGINX access and error logs.
    *   **LXCs**: `953` (NGINX Gateway)
    *   **Use Case**: Storing logs on a shared volume simplifies log aggregation, analysis, and rotation.

*   **`qdrant_data`**:
    *   **Purpose**: Provides persistent storage for the Qdrant vector database.
    *   **LXCs**: `952` (Qdrant)
    *   **Use Case**: The `qdrant_data` volume ensures that the vector embeddings and collections managed by Qdrant are durable and not lost if the container is recreated.

*   **`n8n_data`**:
    *   **Purpose**: Stores persistent data for the n8n automation platform.
    *   **LXCs**: `954` (n8n)
    *   **Use Case**: This volume preserves n8n workflows, credentials, and execution data.

*   **`ollama_models`**:
    *   **Purpose**: Provides a centralized location for Ollama models.
    *   **LXCs**: `955` (Ollama)
    *   **Use Case**: The `ollama_models` volume allows the Ollama container to access a shared repository of models, saving disk space and simplifying model management.

*   **`llamacpp_models`**:
    *   **Purpose**: Provides a centralized location for Llama.cpp models.
    *   **LXCs**: `957` (Llama.cpp)
    *   **Use Case**: Similar to the other model volumes, this allows for efficient storage and access to models for the Llama.cpp service.

*   **`vllm_models`**:
    *   **Purpose**: Provides a centralized location for Hugging Face models used by vLLM.
    *   **LXCs**: `950` (vLLM), `951` (vLLM)
    *   **Use Case**: The `vllm_models` volume allows multiple vLLM containers to access the same models without duplication, saving significant disk space and simplifying model management.

## NGINX Gateway Summary

The NGINX gateway serves as a central reverse proxy, providing a single entry point for accessing various backend services. This simplifies service discovery, centralizes access control, and provides a unified API for clients.

```mermaid
graph TD
    subgraph Clients
        User[User/Client]
    end

    subgraph "NGINX Gateway [LXC 953]"
        NGINX
    end

    subgraph "Backend Services"
        subgraph "vLLM Services"
            Embedding["LXC 951 - Embedding Service"]
            Granite["LXC 950 - Granite Service"]
        end
        Qdrant["LXC 952 - Qdrant"]
        N8N["LXC 954 - n8n"]
        WebUI["LXC 956 - Open WebUI"]
        Ollama["LXC 955 - Ollama"]
        LlamaCPP["LXC 957 - Llama.cpp"]
    end

    User -- "/v1/embeddings" --> NGINX
    User -- "/v1/chat/completions" --> NGINX
    User -- "/qdrant/" --> NGINX
    User -- "/n8n/" --> NGINX
    User -- "/webui/" --> NGINX
    User -- "/ollama/" --> NGINX
    User -- "/llamacpp/" --> NGINX

    NGINX -- "model=embedding" --> Embedding
    NGINX -- "model=granite-3.3-8b-instruct" --> Granite
    NGINX -- "/qdrant/" --> Qdrant
    NGINX -- "/n8n/" --> N8N
    NGINX -- "/webui/" --> WebUI
    NGINX -- "/ollama/" --> Ollama
    NGINX -- "/llamacpp/" --> LlamaCPP
```

The following service endpoints are configured:

*   **`/v1/chat/completions`**, **`/v1/completions`**, **`/v1/embeddings`**:
    *   **Service**: vLLM and other language model services.
    *   **Routing**: The gateway dynamically routes requests to the appropriate backend service based on the `model` name in the request body. This is achieved using a JavaScript function (`http.get_model`) and a `map` directive.
    *   **Use Case**: These endpoints provide a standard OpenAI-compatible API for interacting with various language models, abstracting the underlying service implementation from the client.

*   **`/qdrant/`**:
    *   **Service**: Qdrant vector database.
    *   **Routing**: Requests are forwarded to the `qdrant_service` upstream.
    *   **Use Case**: The `/qdrant/` endpoint exposes the Qdrant API, allowing clients to store and query vector embeddings.

*   **`/n8n/`**:
    *   **Service**: n8n automation platform.
    *   **Routing**: Requests are forwarded to the `n8n_service` upstream.
    *   **Use Case**: The `/n8n/` endpoint exposes the n8n UI and API, allowing users to build and manage workflows through a single, consistent gateway address.

*   **`/webui/`**:
    *   **Service**: Open WebUI for language models.
    *   **Routing**: Requests are forwarded to the `open_webui_service` upstream, with support for WebSocket connections.
    *   **Use Case**: This endpoint provides access to a user-friendly web interface for interacting with language models.

*   **`/ollama/`**:
    *   **Service**: Ollama model service.
    *   **Routing**: Requests are forwarded to the `ollama_service` upstream.
    *   **Use Case**: This endpoint exposes the Ollama API, allowing clients to interact with models managed by Ollama.

*   **`/llamacpp/`**:
    *   **Service**: Llama.cpp model service.
    *   **Routing**: Requests are forwarded to the `llamacpp_service` upstream.
    *   **Use Case**: This endpoint exposes the Llama.cpp API, providing another option for running and interacting with language models.