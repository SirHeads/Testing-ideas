---
title: "Phoenix Hypervisor: Docker-in-LXC Deprecation"
summary: "This document records the deprecation of the Docker-in-LXC approach in favor of a dedicated VM for Docker workloads."
document_type: "Architectural Decision Record"
status: "Accepted"
version: "1.0.0"
author: "Roo"
owner: "Technology Team"
tags:
  - "Phoenix Hypervisor"
  - "Docker"
  - "LXC"
  - "Mitigation"
  - "fuse"
review_cadence: "Ad-hoc"
---

## 1. Executive Summary

This document records the decision to deprecate the use of Docker within LXC containers in favor of a dedicated VM-based approach for all Docker workloads. This change resolves the persistent startup failures related to `fuse` mounts and aligns with best practices for security and isolation.

## 2. Issue Description

The use of Docker within unprivileged LXC containers presented persistent challenges, primarily related to the mounting of `/dev/fuse` and other security-related complexities. These issues led to unreliable container startups and blocked the deployment of Docker-dependent services.

## 3. Resolution

The designated replacement for all Docker-in-LXC workloads is VM 1001 (`Dr-Phoenix`). This dedicated Virtual Machine provides a more stable and secure environment for Docker, eliminating the complexities of nested containerization.

## 4. Conclusion

The Docker-in-LXC approach has been officially deprecated. All future Docker workloads will be deployed within VM 1001 (`Dr-Phoenix`), and the `Template-Docker` and `Template-Docker-GPU` LXC templates have been removed from the system.