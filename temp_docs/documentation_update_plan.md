# Documentation and Configuration Update Plan

This document outlines the necessary updates to the project's documentation and configuration files based on recent changes to VM 1001, Docker, Portainer, Nginx (LXC 101), and vLLM (LXC 801).

## 1. VM 1001 (Dr-Phoenix) - Docker & Portainer Host

**Context:** VM 1001 (`Dr-Phoenix`) is now the dedicated host for Docker and the Portainer management UI. This centralizes container management and moves away from the deprecated Docker-in-LXC model for better stability and security.

### Files to Update:

1.  **`usr/local/phoenix_hypervisor/etc/phoenix_vm_configs.json`**
    *   **Change:** Ensure the configuration for VM 1001 correctly reflects its role.
    *   **Details:**
        *   Verify the `features` array includes `"docker"`.
        *   Verify the `portainer_config` object points to the correct `docker-compose.yml` path: `"/usr/local/phoenix_hypervisor/persistent-storage/portainer/docker-compose.yml"`.

2.  **`Thinkheads.AI_docs/02_technical_strategy_and_architecture/26_phoenix_hypervisor_unified_architecture_guide.md`**
    *   **Change:** Update the architecture guide to explicitly state that VM 1001 is the sole, recommended host for Docker and Portainer.
    *   **Details:**
        *   In the "Docker Integration" section, specifically name VM 1001 (`Dr-Phoenix`) as the dedicated VM.
        *   Update any Mermaid diagrams to show Portainer and other Docker services running within VM 1001, not in an LXC container.

3.  **`Thinkheads.AI_docs/03_phoenix_hypervisor_implementation/04_feature_summaries/05_feature_portainer_summary.md`**
    *   **Change:** Reinforce the architectural shift to a VM-based deployment for Portainer.
    *   **Details:**
        *   Update the summary to explicitly mention VM 1001 as the primary example of a dedicated VM for Portainer.
        *   Ensure the link to the `12_docker_lxc_issue_mitigation_plan.md` is correct and the text emphasizes this deprecation.

4.  **`Thinkheads.AI_docs/03_phoenix_hypervisor_implementation/00_guides/12_docker_lxc_issue_mitigation_plan.md`**
    *   **Change:** Update the mitigation plan to reflect the completed migration.
    *   **Details:**
        *   Change the status from a "plan" to a "record" of the decision.
        *   Explicitly state that VM 1001 (`Dr-Phoenix`) is the designated replacement for all Docker-in-LXC workloads.

## 2. Nginx Gateway (LXC 101)

**Context:** The Nginx gateway (LXC 101) needs to be updated to route traffic to the new vLLM embedding service (LXC 801).

### Files to Update:

1.  **`usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`**
    *   **Change:** Add a dependency for LXC 101 on LXC 801.
    *   **Details:**
        *   In the configuration for CTID `101`, add `"801"` to the `dependencies` array. This ensures 801 is started before 101.

2.  **`usr/local/phoenix_hypervisor/etc/nginx/sites-available/vllm_gateway`**
    *   **Change:** Add a new upstream and location block to proxy requests to the vLLM service.
    *   **Details:**
        *   Add an `upstream` block for the embedding service:
            ```nginx
            upstream vllm_embedding_service {
                server 10.0.0.141:8000;
            }
            ```
        *   In the main `server` block, add a `location` block to handle requests for the embedding model:
            ```nginx
            location /v1/embeddings {
                proxy_pass http://vllm_embedding_service;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            }
            ```

3.  **`Thinkheads.AI_docs/03_phoenix_hypervisor_implementation/00_guides/02_lxc_container_implementation_guide.md`**
    *   **Change:** Update the documentation for the Nginx container (953 in the doc, but conceptually 101) to include its role in routing to the vLLM service.
    *   **Details:**
        *   Add a bullet point under "Functionality" for routing to the vLLM embedding service.
        *   Update any diagrams to show the connection from the Nginx gateway to LXC 801.

## 3. vLLM Embedding Service (LXC 801)

**Context:** LXC 801 is a new container that serves the `granite-embedding` model via vLLM. Its documentation needs to be created or updated.

### Files to Update:

1.  **`Thinkheads.AI_docs/03_phoenix_hypervisor_implementation/00_guides/02_lxc_container_implementation_guide.md`**
    *   **Change:** Add a new section for container 801.
    *   **Details:**
        *   Create a new heading: `### Container 801: Embedding Service (granite-embedding)`.
        *   Add details:
            *   **Purpose**: Hosts a vLLM instance serving the `ibm-granite/granite-embedding-english-r2` model.
            *   **Key Software**: vLLM
            *   **Resource Allocation**: CPU: 6 cores, Memory: 72000 MB, Storage: 128 GB, GPU: Passthrough of GPU `0`.
            *   **Configuration Details**: IP Address: `10.0.0.141`, Port: `8000`, Dependencies: `101`.

2.  **`Thinkheads.AI_docs/03_phoenix_hypervisor_implementation/04_feature_summaries/02_feature_vllm_summary.md`**
    *   **Change:** Update the vLLM feature summary to include the new embedding model as a usage example.
    *   **Details:**
        *   Mention that the `vllm` feature is used to power embedding models, citing LXC 801 and the `granite-embedding` model as a prime example.