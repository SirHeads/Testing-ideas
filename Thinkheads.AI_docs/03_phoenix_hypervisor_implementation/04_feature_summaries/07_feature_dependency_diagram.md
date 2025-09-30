---
title: 'Feature Dependency Diagram'
summary: A Mermaid diagram illustrating the relationships and dependencies between the LXC features in the Phoenix Hypervisor ecosystem.
document_type: "Diagram"
status: "Approved"
version: "1.0.0"
author: "Phoenix Hypervisor Team"
owner: "Developer"
tags:
  - "Mermaid"
  - "Diagram"
  - "Dependencies"
  - "Architecture"
review_cadence: "Annual"
last_reviewed: "2025-09-30"
---

## Feature Dependency Diagram

This diagram shows the dependencies between the modular features used to provision LXC containers. An arrow from one feature to another indicates that the source feature is a prerequisite for the target feature.

```mermaid
graph TD
    subgraph "Core Features"
        A[base_setup]
        B[python_api_service]
        C[nvidia]
    end

    subgraph "Containerization"
        D[docker]
    end

    subgraph "Applications & Services"
        E[portainer]
        F[ollama]
        G[vllm]
    end

    A --> B
    A --> C
    A --> D
    
    C --> D
    B --> G
    C --> F
    C --> G

    D --> E