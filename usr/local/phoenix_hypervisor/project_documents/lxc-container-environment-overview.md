---
title: "LXC Container Environment: An Overview"
summary: This document provides a detailed overview of the LXC container environment, including the network topology and container communication pathways.
document_type: Technical
status: Draft
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Team/Individual Name
tags:
- Phoenix Hypervisor
- Architecture
- LXC
- Networking
review_cadence: Annual
---

## 1. Introduction

The Phoenix Hypervisor project utilizes a straightforward and robust networking model for its LXC containers. All containers are connected to a single bridge, `vmbr0`, which provides a unified network for all virtualized resources.

## 2. Network Diagram

The following diagram illustrates the network topology of the LXC container environment.

```mermaid
graph TD
    subgraph Internet
        A[Gateway: 10.0.0.1]
    end

    subgraph Proxmox Host
        B[vmbr0]
    end

    subgraph LXC Containers
        C[NGINX Gateway - 10.0.0.153]
        D[vLLM Granite 3B - 10.0.0.150]
        E[vLLM Granite Embed - 10.0.0.151]
        F[Qdrant - 10.0.0.152]
        G[n8n - 10.0.0.154]
        H[Ollama - 10.0.0.155]
        I[OpenWebUI - 10.0.0.156]
        J[LlamaCPP - 10.0.0.157]
        K[Portainer - 10.0.0.99]
    end

    A -- Connects to --> B
    B -- Connects to --> C
    B -- Connects to --> D
    B -- Connects to --> E
    B -- Connects to --> F
    B -- Connects to --> G
    B -- Connects to --> H
    B -- Connects to --> I
    B -- Connects to --> J
    B -- Connects to --> K

    C -- Proxies requests to --> D
    C -- Proxies requests to --> E
    C -- Proxies requests to --> F
    C -- Proxies requests to --> G
    C -- Proxies requests to --> H
    C -- Proxies requests to --> I
    C -- Proxies requests to --> J
    C -- Proxies requests to --> K