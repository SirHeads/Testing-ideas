---
title: 'AI/ML Desktop Environment: Project Summary'
summary: This project aims to create a functional and efficient Linux desktop environment within an LXC container on a Proxmox 9 host, optimized for AI/ML workloads.
document_type: Business Case
status: Draft
version: '1.0'
author: Roo
owner: Thinkheads.AI
tags:
  - ai_ml
  - desktop_environment
  - project_summary
review_cadence: Annual
last_reviewed: '2025-09-23'
---
This project aims to create a functional and efficient Linux desktop environment within an LXC container on a Proxmox 9 host. The environment will be optimized for AI/ML workloads, learning, and remote access. It will leverage two NVIDIA 5060 Ti 16GB GPUs for hardware acceleration and utilize lightweight desktop components to minimize overhead.

## Overview
This project aims to create a functional and efficient Linux desktop environment within an LXC container on a Proxmox 9 host. The environment will be optimized for AI/ML workloads, learning, and remote access. It will leverage two NVIDIA 5060 Ti 16GB GPUs for hardware acceleration and utilize lightweight desktop components to minimize overhead.

The primary goals are to achieve strong isolation, seamless GPU passthrough, high-performance remote desktop access via RustDesk, and a scalable architecture that allows for the creation of multiple, similar containerized environments. This initiative is based on successful implementations and best practices gathered from the Proxmox and homelab communities.
