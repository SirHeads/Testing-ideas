---
title: Document Title
summary: A brief, one-to-two-sentence summary of the document's purpose and content.
document_type: Strategy | Technical | Business Case | Report
status: Draft | In Review | Approved | Archived
version: 1.0.0
author: Author Name
owner: Team/Individual Name
tags: []
review_cadence: Annual | Quarterly | Monthly | None
last_reviewed: YYYY-MM-DD
---
# ThinkHeads.ai Project Roadmap

## Overview
The ThinkHeads.ai project roadmap outlines the timeline, phases, and milestones for developing five sub-products: AI-driven website, Learning Assistant, Meeting Room, Online Card Game, and User Profiles. The roadmap aligns with the goals of mastering AI/ML/DL, building a job-ready portfolio, and achieving community engagement within 12 months. It accounts for solo development, a 20-hour/week schedule, and resource constraints (Proxmox server: AMD 7700, 96 GB DDR5, dual RTX 5060 Ti GPUs, NVMe storage; Linode server: 4 GB RAM, 2 CPU cores, 80 GB storage). The roadmap is structured for human readability and RAG integration to support strategic planning via the Meeting Room sub-product.

## Phases and Timeline
The development is divided into three phases, spanning July 2025 to July 2026, with high-priority projects (AI-driven website, Learning Assistant, Meeting Room) targeted for MVP completion within 4-6 months, and lower-priority projects (User Profiles, Online Card Game) within 9 months.

- **Phase 1: Infrastructure Setup and High-Priority Foundations (July 2025 - October 2025, 4 months)**
  - Focus: Establish infrastructure, deploy AI-driven website, and start Learning Assistant and Meeting Room.
  - Estimated Effort: ~320 hours (20 hours/week × 16 weeks).
- **Phase 2: Core Feature Development (November 2025 - February 2026, 4 months)**
  - Focus: Complete MVPs for Learning Assistant and Meeting Room, begin User Profiles.
  - Estimated Effort: ~320 hours (20 hours/week × 16 weeks).
- **Phase 3: Community Features and Polish (March 2026 - July 2026, 5 months)**
  - Focus: Develop Online Card Game, complete User Profiles, and enhance portfolio for job applications.
  - Estimated Effort: ~400 hours (20 hours/week × 20 weeks).

## Milestones by Sub-Product
The table below details milestones for each sub-product, including feature IDs (from **2.2 Feature_Backlog.md**), completion dates, and dependencies. Milestones are aligned with the prioritization from **3.1 Project_Selection_Criteria.md**.

| Sub-Product         | Milestone Description                              | Feature IDs | Completion Date | Dependencies                     |
|---------------------|---------------------------------------------------|-------------|-----------------|----------------------------------|
| **AI-Driven Website** | Infrastructure setup (Proxmox, Linode, Cloudflare) | -           | Aug 2025        | None                             |
|                     | Static site live (Hugo, Nginx)                   | F02         | Sep 2025        | Infrastructure setup             |
|                     | Chat-based navigation MVP (Ollama, FastAPI)      | F01, F03    | Oct 2025        | Infrastructure, PostgreSQL       |
| **Learning Assistant** | RAG pipeline setup (Ollama, PostgreSQL)          | F04         | Oct 2025        | Infrastructure, AI-driven website |
|                     | Note-taking system MVP                           | F05         | Dec 2025        | RAG pipeline, PostgreSQL         |
|                     | Reinforcement learning exercises                 | F06         | Feb 2026        | Note-taking system               |
| **Meeting Room**    | RAG-powered LLM for planning                     | F07         | Nov 2025        | Infrastructure, PostgreSQL, RAG   |
|                     | Exportable strategy plans                        | F08         | Jan 2026        | RAG-powered LLM, FastAPI         |
|                     | Secure remote access (RustDesk, Cloudflare)      | F09         | Jan 2026        | Infrastructure, RAG-powered LLM  |
| **User Profiles**   | Webcam photo upload and storage                  | F13         | Feb 2026        | Infrastructure, PostgreSQL, FastAPI |
|                     | Overnight avatar generation (Imagen, n8n)        | F14         | Apr 2026        | Photo upload, Proxmox GPU        |
|                     | Public profile pages                             | F15         | May 2026        | Avatar generation, Nginx         |
| **Online Card Game**| Multiplayer gameplay MVP (WebSocket, FastAPI)    | F10         | May 2026        | Infrastructure, PostgreSQL, Nginx |
|                     | Game state storage                               | F11         | Jun 2026        | Multiplayer gameplay             |
|                     | AI-generated card visuals (Imagen)               | F12         | Jul 2026        | Multiplayer gameplay, Proxmox GPU |

## Dependencies and Resource Allocation
- **Infrastructure Setup** (Aug 2025):
  - **Proxmox**: Configure LXC containers (`dockProd1` for Ollama, `dockProd2` for PostgreSQL/Imagen, `dockTest1` for testing), VM for ML desktop, GPU passthrough.
  - **Linode**: Set up Debian, Docker, Nginx, Hugo, Cloudflare Tunnel.
  - **Automation**: n8n workflows for backups (rsync), monitoring, and scheduling.
  - **Dependencies**: None, foundational for all projects.
- **AI-Driven Website**:
  - Depends on infrastructure for hosting and PostgreSQL for chat session storage.
  - Uses Proxmox (`dockProd1`) for Ollama and Linode for Hugo/Nginx.
- **Learning Assistant**:
  - Depends on AI-driven website for RAG pipeline and PostgreSQL integration.
  - Uses Proxmox GPU for Ollama, PostgreSQL on `dockProd2`.
- **Meeting Room**:
  - Depends on RAG pipeline and PostgreSQL for document embeddings.
  - Uses Proxmox (`dockProd1`) for Ollama, RustDesk for access.
- **User Profiles**:
  - Depends on infrastructure, PostgreSQL, and Proxmox GPU for Imagen.
  - Uses n8n for overnight processing, Linode for profile hosting.
- **Online Card Game**:
  - Depends on infrastructure and PostgreSQL for game state.
  - Uses Linode for WebSocket (FastAPI), Proxmox for Imagen visuals.
- **Resource Scheduling**:
  - GPU tasks (F01, F04, F07, F12, F14) are staggered to avoid conflicts (e.g., dynamic GPU release between `dockProd1` and `dockProd2`).
  - Linode’s 4 GB RAM prioritizes static content (F02, F15) and lightweight APIs (F03, F10).

## Constraints
- **Time**: 20 hours/week limits parallel development. High-priority projects (AI-driven website, Learning Assistant, Meeting Room) require ~200-240 hours, spread over 4-6 months.
- **Resources**:
  - Proxmox supports GPU-intensive tasks but requires careful scheduling for dual RTX 5060 Ti GPUs.
  - Linode’s 4 GB RAM limits complex backend services; offload AI tasks to Proxmox.
- **Solo Operation**: Automation (n8n) and AI tools (Ollama, Imagen) maximize productivity. No external human collaborators.
- **Tech Stack**: Leverages existing tools (Cloudflare, Nginx, PostgreSQL, Python/FastAPI, Ollama, n8n, RustDesk, Hugo, Imagen) to minimize learning overhead.

## RAG Integration
- **Usage**: This document feeds into the Meeting Room sub-product’s RAG pipeline (Ollama, PostgreSQL) to track progress and refine schedules.
- **Structure**: Consistent headers, tables, and metadata ensure parseability. Milestones and dependencies provide context for LLM-driven planning.
- **Storage**: Store in Git repository on Proxmox, sync to Linode for public access on ThinkHeads.ai, embed in PostgreSQL for RAG queries.

## Success Metrics
- **Milestone Completion**: Achieve all Phase 1 milestones by Oct 2025, Phase 2 by Feb 2026, and Phase 3 by Jul 2026.
- **Learning Outcomes**: Master LLM integration (F01, F04, F07), RAG (F04, F07), and image processing (F12, F14) through project milestones.
- **Portfolio Impact**: Deploy MVPs for high-priority projects (AI-driven website, Learning Assistant, Meeting Room) on ThinkHeads.ai by Feb 2026, achieving 10+ employer views via X/LinkedIn.
- **Engagement**: Attract 10+ active users to Online Card Game and User Profiles by Jul 2026.
- **Performance**: Maintain 99% uptime for Linode services and ensure low latency (e.g., <2s for LLM responses, <10s for avatar generation).
