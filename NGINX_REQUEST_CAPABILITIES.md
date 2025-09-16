# NGINX Gateway Request Capabilities

This document provides a detailed breakdown of the types of requests that the NGINX gateway is configured to handle for each backend service.

---

## 1. n8n (`n8n_proxy`)

*   **Endpoint:** `https://n8n.phoenix.local/`
*   **Handled Requests:**
    *   **Standard HTTP/HTTPS:** All standard web traffic (GET, POST, etc.) to the n8n web UI.
    *   **WebSocket:** The configuration includes the necessary headers (`Upgrade`, `Connection`) to support WebSocket connections, which are essential for the interactive functionality of the n8n UI.

---

## 2. Portainer (`portainer_proxy`)

*   **Endpoint:** `https://portainer.phoenix.local/`
*   **Handled Requests:**
    *   **Standard HTTP/HTTPS:** All standard web traffic to the Portainer web UI.
    *   **WebSocket:** The configuration supports WebSocket connections, which Portainer uses for real-time communication with the Docker host (e.g., for viewing container logs).

---

## 3. Ollama (`ollama_proxy` and `vllm_gateway`)

*   **Endpoints:** `http://10.0.0.153/ollama/` and `/ollama/` within the `vllm_gateway`.
*   **Handled Requests:**
    *   **API Requests:** Standard HTTP requests (POST, GET) to the Ollama API for interacting with language models (e.g., generating text, listing models).

---

## 4. vLLM Services (`vllm_gateway`)

*   **Endpoints:** `/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`
*   **Handled Requests:**
    *   **OpenAI-Compatible API Requests:** The gateway handles POST requests to these endpoints, which are designed to be compatible with the OpenAI API.
    *   **Dynamic Routing:** The key capability here is the dynamic routing based on the `model` name in the JSON payload of the request. The `http.js` script extracts the model name, and the `map` directive routes the request to the appropriate backend service (e.g., `embedding_service` or `qwen_service`).

---

## 5. Qdrant (`vllm_gateway`)

*   **Endpoint:** `/qdrant/`
*   **Handled Requests:**
    *   **API Requests:** All standard HTTP requests to the Qdrant vector database API. This includes creating and managing collections, adding and searching for vectors, etc.

---

## 6. Open WebUI (`vllm_gateway`)

*   **Endpoint:** `/webui/`
*   **Handled Requests:**
    *   **Standard HTTP/HTTPS:** All standard web traffic to the Open WebUI.
    *   **WebSocket:** The configuration supports WebSocket connections for real-time, interactive chat sessions with the language models.

---

## 7. Llama.cpp (`vllm_gateway`)

*   **Endpoint:** `/llamacpp/`
*   **Handled Requests:**
    *   **API Requests:** Standard HTTP requests to the Llama.cpp server's API, which provides another way to interact with language models.