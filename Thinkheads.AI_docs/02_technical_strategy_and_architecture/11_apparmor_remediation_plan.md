---
title: AppArmor Remediation and Architectural Redesign
summary: A plan for refactoring the AppArmor implementation to be more robust, flexible, and configuration-driven.
document_type: Architectural Plan
status: Proposed
version: 2.0.0
author: Roo
owner: Technical VP
tags:
  - AppArmor
  - Remediation
  - Architecture
  - Security
  - LXC
  - GPU
  - Docker
review_cadence: Annual
last_reviewed: 2025-09-30
---

# AppArmor Remediation and Architectural Redesign

This document outlines a new, more robust, and flexible architecture for managing AppArmor profiles within the Phoenix project. This redesign addresses the limitations of the current implementation and provides a more scalable and maintainable solution for securing LXC containers.

## 1. Current State Analysis

The current implementation has the following weaknesses:

*   **Redundant Logic:** AppArmor profile deployment logic is duplicated in both `phoenix_orchestrator.sh` and `hypervisor_feature_setup_apparmor.sh`, leading to potential inconsistencies.
*   **Inconsistent Naming:** The existing AppArmor profile names (`lxc-docker-nested`, `lxc-gpu-docker-storage`, etc.) lack a clear and consistent naming convention.
*   **Outdated Documentation:** The existing remediation plan does not accurately reflect the current state of the codebase.

## 2. Proposed Architecture

To address these issues, the following changes are proposed:

### 2.1. Centralized Deployment Logic

The `hypervisor_feature_setup_apparmor.sh` script will be the single source of truth for deploying and reloading AppArmor profiles. The `phoenix_orchestrator.sh` script will no longer be responsible for copying profiles.

### 2.2. Standardized Profile Naming

A new, standardized naming convention will be adopted for all AppArmor profiles:

*   `lxc-phoenix-v2`: A comprehensive profile for containers requiring Docker, GPU, and nesting support.
*   `lxc-phoenix-v1`: A legacy profile to be deprecated.
*   `lxc-nesting-v1`: A profile for basic nesting.
*   `lxc-gpu-docker-storage`: A profile for GPU, Docker, and storage.
*   `lxc-docker-nested`: A profile for nested Docker containers.

### 2.3. Configuration-Driven Profile Assignment

The `phoenix_lxc_configs.json` schema will continue to use the `apparmor_profile` key for explicit and declarative profile assignment.

## 3. Implementation Details

### 3.1. Project Structure

The project structure will be updated as follows:

```
/usr/local/phoenix_hypervisor/
|-- etc/
|   |-- apparmor/
|   |   |-- lxc-phoenix-v2
|   |   |-- lxc-phoenix-v1
|   |   |-- lxc-nesting-v1
|   |   |-- lxc-gpu-docker-storage
|   |   `-- lxc-docker-nested
|   |-- phoenix_lxc_configs.json
|   `-- phoenix_lxc_configs.schema.json
|-- bin/
|   |-- hypervisor_setup/
|   |   `-- hypervisor_feature_setup_apparmor.sh
|   `-- phoenix_orchestrator.sh
```

### 3.2. Enhanced Setup Script

The `hypervisor_feature_setup_apparmor.sh` script will be modified to:

1.  **Iterate Through Profiles:** Loop through all files in the `etc/apparmor/` directory.
2.  **Idempotent Copy:** Copy each profile to `/etc/apparmor.d/` only if it's new or has been updated.
3.  **Reload AppArmor:** Reload the AppArmor service to apply the changes.

### 3.3. Improved Orchestration Logic

The `phoenix_orchestrator.sh` script will be updated to:

1.  **Read `apparmor_profile`:** Retrieve the value of the `apparmor_profile` key from the container's JSON configuration.
2.  **Handle `unconfined`:** If the profile is set to `"unconfined"`, ensure that no `lxc.apparmor.profile` line is present in the container's `.conf` file.
3.  **Apply Profile:** If a specific profile is defined, idempotently set the `lxc.apparmor.profile` in the container's `.conf` file to the specified value.

## 4. Summary and Workflow

This new architecture provides a more robust, flexible, and transparent way to manage AppArmor profiles. By centralizing the deployment logic and standardizing the naming convention, we improve the maintainability and scalability of the system.

### Workflow Diagram:

```mermaid
graph TD
    A[phoenix_orchestrator.sh --setup-hypervisor] --> B{hypervisor_feature_setup_apparmor.sh};
    B --> C[Copies all profiles from etc/apparmor/ to /etc/apparmor.d/];
    C --> D[Reloads AppArmor service];

    E[phoenix_orchestrator.sh <CTID>] --> F{apply_configurations};
    F --> G[Reads apparmor_profile from phoenix_lxc_configs.json];
    G --> H{Profile defined?};
    H -- Yes --> I[Sets lxc.apparmor.profile in <CTID>.conf];
    H -- No/unconfined --> J[Ensures no lxc.apparmor.profile line exists];
