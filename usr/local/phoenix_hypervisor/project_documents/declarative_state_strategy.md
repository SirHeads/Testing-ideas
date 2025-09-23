---
title: Declarative State Strategy
summary: This document outlines the strategy for transitioning the Phoenix Orchestrator from an imperative, script-driven system to a fully declarative, convergent state engine.
document_type: Strategy
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Strategy
- Declarative State
- Idempotency
- IaC
review_cadence: Quarterly
last_reviewed: 2025-09-23
---

# Phoenix Orchestrator: Strategy for a Declarative State Model

## 1. Strategic Objective

The primary strategic objective for the Phoenix Orchestrator is to transition from an imperative, script-driven system to a fully declarative, convergent state engine. This strategic shift is essential for achieving the long-term goals of stability, scalability, and maintainability for the Phoenix Hypervisor platform.

## 2. The Problem with the Imperative Model

The previous model, which relied on a sequence of independent scripts, suffered from several critical flaws that were exposed during recent debugging efforts:

-   **Brittleness**: The system's success was dependent on the precise order and successful execution of every script. A failure in one script could leave the system in an inconsistent, intermediate state.
-   **Lack of Idempotency**: Re-running the orchestrator was not safe. It could lead to errors (e.g., trying to create a resource that already exists) or fail to correct underlying configuration drift.
-   **Divergence from Source of Truth**: The configuration files described a desired state, but there was no guarantee that the scripts would accurately or completely implement that state. This led to a system that was difficult to understand and debug.

## 3. The Declarative Strategy

Our strategy is to refactor the orchestrator and its component scripts to adhere to the principles of modern Infrastructure-as-Code (IaC).

### 3.1. Embrace the Convergent Model

The core of the strategy is the adoption of the "Inspect, Compare, Converge" loop for all resource management. This means that every component of the orchestrator will be responsible not just for *creating* resources, but for *managing their entire lifecycle*.

-   **Short-Term**: The immediate implementation, as seen in the `hypervisor_feature_setup_zfs.sh` script, is to apply this logic at the feature level. Each setup script will be refactored to be a self-contained state engine for the feature it manages.
-   **Long-Term**: The ultimate goal is to centralize this logic within the main `phoenix_orchestrator.sh` script. The orchestrator itself will become a master state engine that calls feature-specific modules to inspect and converge resources. This will create a more cohesive and powerful system.

### 3.2. Configuration as Code

The JSON configuration files will be treated as the definitive "code" that describes the system. All changes to the infrastructure will be made by modifying these files and then running the orchestrator to apply the changes. This ensures that every change is deliberate, version-controlled, and peer-reviewed.

### 3.3. Phased Rollout

The transition to a fully declarative model will be a phased process:

1.  **Phase 1 (Complete)**: Refactor the `hypervisor_feature_setup_zfs.sh` script to be fully convergent. This serves as the blueprint for future refactoring.
2.  **Phase 2**: Apply the same convergent logic to the other setup scripts (`NFS`, `Samba`, `NVIDIA`, etc.).
3.  **Phase 3**: Refactor the container orchestration logic (`orchestrate_container` function) to be fully declarative, managing container state (running, stopped, configured) based on the config file.
4.  **Phase 4**: Centralize the state management logic into the main orchestrator, turning it into a true master state engine.

## 4. Expected Outcomes

By executing this strategy, we will transform the Phoenix Orchestrator into a modern, robust, and reliable platform that is:

-   **Resilient**: It can recover from partial failures and automatically correct configuration drift.
-   **Scalable**: New resources and features can be added easily by extending the declarative model.
-   **Auditable**: The state of the system is clearly defined in version-controlled configuration files.