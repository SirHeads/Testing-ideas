---
title: Technology Stack
summary: This document outlines the technology stack for Thinkheads.AI.
document_type: Strategy
status: Approved
version: 1.0.0
author: Thinkheads.AI
owner: Thinkheads.AI
tags:
- Technology Stack
- Strategy
- Technical
review_cadence: Quarterly
last_reviewed: 2025-09-23
---
# ThinkHeads.ai Technology Stack

## Overview
The ThinkHeads.ai technology stack is designed to support AI-driven project development, portfolio showcasing, and efficient solo operation. It leverages a combination of local and cloud infrastructure, open-source tools, and automation to enable rapid learning and deployment of AI/ML/DL applications. The stack is optimized for scalability, security, and cost-efficiency, aligning with the goal of building a job-ready portfolio in artificial intelligence.

## Hardware Infrastructure
- **Local Proxmox Server**:
  - **Specifications**: AMD 7700 CPU, 96 GB DDR5 RAM, dual RTX 5060 Ti GPUs, NVMe storage (1 TB).
  - **Role**: Hosts compute-intensive tasks, including LLM training (Ollama), image processing (Imagen), and development environments.
  - **Configuration**:
    - Proxmox VE for virtualization.
    - LXC containers: `dockProd1` (LLM hosting, 1 RTX 5060 Ti), `dockProd2` (image processing, PostgreSQL, dynamic GPU access), `dockTest1` (testing).
    - VM for ML desktop with GPU passthrough for interactive development.
    - Network: Shared network, SSH access, RustDesk for remote management.
- **Linode Cloud Server**:
  - **Specifications**: 4 GB RAM, 2 CPU cores, 80 GB SSD storage, Debian OS.
  - **Role**: Hosts public-facing ThinkHeads.ai website and lightweight services.
  - **Configuration**: Docker for production/test environments, Nginx for web serving, Cloudflare Tunnel for secure access.

## Software Stack
- **Cloudflare**:
  - **Role**: DNS management, DDoS protection, and secure access to Linode server.
  - **Usage**: Configures DNS for ThinkHeads.ai, enables Cloudflare Tunnel for secure remote access to services, and provides performance optimization (e.g., caching).
- **Nginx**:
  - **Role**: Web server for ThinkHeads.ai and API reverse proxy.
  - **Usage**: Serves static Hugo site on Linode, proxies API requests to FastAPI, supports SSL/TLS for secure connections.
- **PostgreSQL**:
  - **Role**: Database for storing user data, project metadata, and RAG embeddings.
  - **Usage**: Hosted in LXC container (`dockProd2`) on Proxmox for development and Linode for production. Stores game states (Online Card Game), user profiles, and learning notes (Learning Assistant).
- **Python/FastAPI**:
  - **Role**: Backend API development for dynamic features and integrations.
  - **Usage**: Powers APIs for chat interface (AI-driven website), note-taking (Learning Assistant), strategy outputs (Meeting Room), game logic (Online Card Game), and avatar processing (User Profiles). Hosted in Docker on Linode and LXC on Proxmox.
- **Linux**:
  - **Role**: Operating system for servers and development environments.
  - **Usage**: Debian on Linode for stability, Ubuntu in Proxmox LXC/VMs for development flexibility. Manages all server operations and scripting.
- **Proxmox VE**:
  - **Role**: Virtualization platform for local server.
  - **Usage**: Manages LXC containers and VMs, allocates GPU resources for ML tasks, supports isolated environments for production (dockProd1, dockProd2) and testing (dockTest1).
- **RustDesk**:
  - **Role**: Remote desktop and server management.
  - **Usage**: Provides secure access to Proxmox server and ML desktop VM for monitoring and development from any location.
- **n8n**:
  - **Role**: Workflow automation for repetitive tasks.
  - **Usage**: Automates backups (rsync to Linode), deployment updates (Docker pulls), monitoring (resource usage alerts), and scheduling (e.g., overnight avatar processing). Hosted in LXC container on Proxmox.
- **Ollama**:
  - **Role**: Local LLM hosting for AI-driven features and RAG.
  - **Usage**: Runs fine-tuned LLMs in `dockProd1` for chat interface (AI-driven website), Learning Assistant, and Meeting Room. Supports RAG with markdown documents stored in PostgreSQL.
- **Hugo**:
  - **Role**: Static site generator for ThinkHeads.ai.
  - **Usage**: Generates public-facing website on Linode, hosting markdown documentation, project demos, and blog posts. Lightweight and fast, integrated with Nginx.
- **Imagen (or equivalent AI image model)**:
  - **Role**: AI-powered image processing for User Profiles.
  - **Usage**: Generates avatars from webcam photos, running in `dockProd2` with GPU support. Processes images overnight via n8n-scheduled workflows.
- **Git**:
  - **Role**: Version control for code and documentation.
  - **Usage**: Stores markdown files and project code in a repository on Proxmox, synced to Linode for public access. Supports collaboration with open-source community if needed.

## Integration Plan
- **Website Hosting**:
  - Hugo generates static site on Linode, served by Nginx.
  - Cloudflare manages DNS and security, with Tunnel for secure API access.
- **AI/ML Workloads**:
  - Ollama and Imagen run in Proxmox LXC containers (`dockProd1`, `dockProd2`) with GPU passthrough for LLM training and image processing.
  - PostgreSQL stores RAG embeddings and project data, accessible via FastAPI.
- **Automation**:
  - n8n workflows automate backups (markdown files, PostgreSQL), deployments (Docker updates), and scheduling (e.g., Learning Assistant sessions, avatar generation).
  - RustDesk enables remote monitoring of Proxmox tasks.
- **Development Workflow**:
  - Code and markdown edited in VS Code on Proxmox VM or local machine.
  - Git pushes updates to Proxmox repository, synced to Linode for public site.
  - FastAPI endpoints handle dynamic features, integrated with Ollama and PostgreSQL.
- **RAG Pipeline**:
  - Markdown documents parsed and embedded using Ollama, stored in PostgreSQL.
  - FastAPI queries embeddings for Meeting Room LLM and Learning Assistant, enabling context-aware responses.

## Scalability and Constraints
- **Scalability**:
  - Hugo and Nginx ensure low-resource website hosting on Linode.
  - Proxmox’s LXC containers allow dynamic resource allocation (e.g., GPU sharing between `dockProd1` and `dockProd2`).
  - Cloudflare caching reduces Linode load for public traffic.
- **Constraints**:
  - Linode’s 4 GB RAM limits complex backend services; offload heavy tasks to Proxmox.
  - Solo operation requires automation (n8n) to manage 20-hour/week time budget.
  - GPU availability (dual RTX 5060 Ti) requires careful scheduling for LLM and image tasks.

## Success Metrics
- **Operational Stability**: Achieve 99% uptime for ThinkHeads.ai (Linode, Nginx, Cloudflare) and Proxmox services.
- **Performance**: Ensure LLM responses (Ollama) under 2 seconds, avatar generation (Imagen) under 10 seconds per image.
- **Automation**: Automate 80% of repetitive tasks (e.g., backups, deployments) via n8n within 3 months.
- **Portfolio Readiness**: Deploy all stack components to support five sub-products within 6 months, documented on ThinkHeads.ai.
