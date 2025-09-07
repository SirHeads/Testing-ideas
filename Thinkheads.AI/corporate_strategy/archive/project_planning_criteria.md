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
# ThinkHeads.ai Project Selection Criteria

## Overview
The project selection criteria for ThinkHeads.ai guide the prioritization and execution of sub-products (AI-driven website, Learning Assistant, Meeting Room, Online Card Game, User Profiles) to maximize AI/ML/DL learning, portfolio impact, and employability. As a solo endeavor, projects are chosen based on their ability to develop relevant skills, showcase technical expertise, and fit within resource constraints (Proxmox server, Linode server, 20 hours/week). This document ensures strategic alignment and is structured for RAG integration to support planning via the Meeting Room sub-product.

## Selection Criteria
Projects are evaluated using the following criteria, each scored on a 1-5 scale (5 = highest):

- **Learning Value**: Contribution to AI/ML/DL skills, such as LLM fine-tuning, RAG implementation, image processing, or full-stack development.
- **Portfolio Impact**: Potential to impress potential employers by demonstrating industry-relevant skills and professional presentation.
- **Technical Feasibility**: Compatibility with available resources (Proxmox: AMD 7700, 96 GB DDR5, dual RTX 5060 Ti GPUs, NVMe storage; Linode: 4 GB RAM, 2 CPU cores, 80 GB storage) and tech stack (Cloudflare, Nginx, PostgreSQL, Python/FastAPI, Ollama, n8n, etc.).
- **Time Feasibility**: Alignment with a 20-hour/week schedule, considering estimated effort and dependencies.
- **Community Engagement**: Potential to attract users (e.g., friends, tech community) to interactive features, boosting portfolio visibility.

## Scoring System
- **Scoring Scale**: 1 (Low) to 5 (High) for each criterion.
- **Weighting**:
  - Learning Value: 30% (critical for skill development).
  - Portfolio Impact: 30% (key for employability).
  - Technical Feasibility: 20% (ensures resource alignment).
  - Time Feasibility: 15% (fits time constraints).
  - Community Engagement: 5% (secondary but valuable for visibility).
- **Total Score**: Weighted sum (out of 5), with projects scoring ≥3.5 prioritized for immediate development.
- **Evaluation Process**: Score each sub-product, rank them, and schedule high-priority projects for MVP completion within 4-6 months.

## Project Evaluations
The table below evaluates each sub-product based on the criteria, with scores and rationale.

| Sub-Product         | Learning Value (30%) | Portfolio Impact (30%) | Technical Feasibility (20%) | Time Feasibility (15%) | Community Engagement (5%) | Total Score |
|---------------------|----------------------|-----------------------|----------------------------|-----------------------|--------------------------|-------------|
| **AI-Driven Website** | 5 (LLM, RAG, APIs)  | 5 (Showcases full-stack, AI) | 4 (Linode, Proxmox viable) | 4 (40-60 hours)       | 3 (Portfolio-focused)    | 4.55        |
| **Learning Assistant** | 5 (RAG, LLM fine-tuning) | 5 (Ed-tech appeal)   | 4 (Proxmox GPU, PostgreSQL)| 3 (80-100 hours)      | 2 (Self-focused)         | 4.35        |
| **Meeting Room**    | 5 (RAG, strategic AI) | 4 (Planning innovation) | 4 (Proxmox, RustDesk)     | 3 (70-80 hours)       | 2 (Self-focused)         | 4.15        |
| **Online Card Game**| 3 (WebSocket, less AI)| 3 (Fun, less job-relevant)| 3 (Linode limits)         | 3 (100-130 hours)     | 5 (Friend engagement)    | 3.25        |
| **User Profiles**   | 4 (Image processing) | 4 (Creative AI, UX)   | 3 (GPU-heavy, Linode limits)| 3 (80-100 hours)      | 4 (User engagement)      | 3.65        |

### Rationale
- **AI-Driven Website (4.55)**:
  - High learning value (LLM integration, RAG, FastAPI).
  - Strong portfolio impact (full-stack AI demo for employers).
  - Feasible with Proxmox (Ollama) and Linode (Hugo, Nginx).
  - Moderate time requirement (40-60 hours over 2 months).
  - Limited community engagement (portfolio-focused).
- **Learning Assistant (4.35)**:
  - High learning value (RAG, fine-tuning, PostgreSQL).
  - Strong portfolio impact (ed-tech relevance).
  - Feasible with Proxmox GPU and PostgreSQL.
  - Higher time requirement (80-100 hours).
  - Self-focused, low community engagement.
- **Meeting Room (4.15)**:
  - High learning value (RAG, strategic AI).
  - Good portfolio impact (innovative planning tool).
  - Feasible with Proxmox and RustDesk.
  - Moderate time requirement (70-80 hours).
  - Self-focused, low community engagement.
- **Online Card Game (3.25)**:
  - Moderate learning value (WebSocket, less AI focus).
  - Moderate portfolio impact (less job-relevant).
  - Constrained by Linode’s 4 GB RAM for multiplayer.
  - High time requirement (100-130 hours).
  - High community engagement (friends).
- **User Profiles (3.65)**:
  - Good learning value (Imagen, automation).
  - Good portfolio impact (creative AI, UX).
  - GPU-heavy, constrained by Linode for hosting.
  - Moderate time requirement (80-100 hours).
  - Good community engagement (user interaction).

## Current Project Priorities
Based on scores, the prioritized projects for immediate development (within 4-6 months) are:
1. **AI-Driven Website**: Highest score (4.55), foundational for portfolio, critical for showcasing AI and full-stack skills.
2. **Learning Assistant**: High score (4.35), accelerates AI/ML/DL learning, strong employer appeal.
3. **Meeting Room**: High score (4.15), supports strategic planning, demonstrates advanced AI use.

Lower-priority projects (6-9 months):
- **User Profiles**: Good score (3.65), but GPU-heavy and less critical for initial portfolio.
- **Online Card Game**: Lowest score (3.25), high effort, prioritized for community engagement later.

## Constraints
- **Time**: 20 hours/week limits parallel development. High-priority projects (200-240 hours total) are spread over 4-6 months.
- **Resources**:
  - Proxmox (96 GB RAM, dual RTX 5060 Ti GPUs) supports AI tasks but requires GPU scheduling (e.g., dynamic release between `dockProd1` and `dockProd2`).
  - Linode (4 GB RAM) limits complex backend services; prioritize static content (Hugo) and offload AI to Proxmox.
- **Solo Operation**: Relies on automation (n8n) and AI tools (Ollama, Imagen) to manage workload. No external human collaborators.
- **Tech Stack**: Must leverage existing tools (Cloudflare, Nginx, PostgreSQL, Python/FastAPI, Ollama, n8n, RustDesk, Hugo, Imagen) to avoid learning overhead.

## RAG Integration
- **Usage**: This document feeds into the Meeting Room sub-product’s RAG pipeline (Ollama, PostgreSQL) to refine project prioritization and planning.
- **Structure**: Consistent headers, tables, and metadata ensure parseability. Scores and rationale provide context for LLM-driven strategy sessions.
- **Storage**: Store in Git repository on Proxmox, sync to Linode for public access on ThinkHeads.ai, and embed in PostgreSQL for RAG queries.

## Success Metrics
- **Prioritization Accuracy**: Select and complete three high-priority projects (AI-Driven Website, Learning Assistant, Meeting Room) within 6 months.
- **Learning Outcomes**: Achieve proficiency in LLM integration, RAG, and full-stack development through prioritized projects.
- **Portfolio Impact**: Showcase prioritized projects on ThinkHeads.ai, achieving 10+ employer views via X/LinkedIn within 9 months.
- **Resource Efficiency**: Stay within Proxmox and Linode resource limits, with 99% uptime for public-facing services.
