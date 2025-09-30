---
title: AppArmor Remediation and Architectural Redesign
summary: A plan for refactoring the AppArmor implementation to be more robust, flexible, and configuration-driven.
document_type: Architectural Plan
status: Implemented
version: 2.1.0
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

This document outlines a new, more robust, and flexible architecture for managing AppArmor profiles within the Phoenix project. This redesign addresses the limitations of the previous implementation and provides a more scalable and maintainable solution for securing LXC containers.

## 1. Previous State Analysis

The previous implementation had the following weaknesses:

*   **Redundant Logic:** AppArmor profile deployment logic was duplicated in both `phoenix_orchestrator.sh` and `hypervisor_feature_setup_apparmor.sh`.
*   **Inconsistent Naming:** The existing AppArmor profile names lacked a clear and consistent naming convention.

## 2. Implemented Architecture

To address these issues, the following changes were implemented:

### 2.1. Centralized Deployment Logic

The `hypervisor_feature_setup_apparmor.sh` script is the single source of truth for deploying and reloading AppArmor profiles. The `lxc-manager.sh` script is responsible for applying the profiles to the containers.

### 2.2. Standardized Profile Naming

A new, standardized naming convention has been adopted for all AppArmor profiles:

*   `lxc-phoenix-v2`: A comprehensive profile for containers requiring Docker, GPU, and nesting support.
*   `lxc-phoenix-v1`: A legacy profile to be deprecated.
*   `lxc-nesting-v1`: A profile for basic nesting.
*   `lxc-gpu-docker-storage`: A profile for GPU, Docker, and storage.
*   `lxc-docker-nested`: A profile for nested Docker containers.

### 2.3. Configuration-Driven Profile Assignment

The `phoenix_lxc_configs.json` schema continues to use the `apparmor_profile` key for explicit and declarative profile assignment.

## 3. Implementation Details

### 3.1. Project Structure

The project structure has been updated as follows:

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
|   |-- managers/
|   |   `-- lxc-manager.sh
|   `-- phoenix
```

### 3.2. Enhanced Setup Script

The `hypervisor_feature_setup_apparmor.sh` script was modified to:

1.  **Iterate Through Profiles:** Loop through all files in the `etc/apparmor/` directory.
2.  **Idempotent Copy:** Copy each profile to `/etc/apparmor.d/` only if it's new or has been updated.
3.  **Reload AppArmor:** Reload the AppArmor service to apply the changes.

### 3.3. Improved Orchestration Logic

The `lxc-manager.sh` script was updated to:

1.  **Read `apparmor_profile`:** Retrieve the value of the `apparmor_profile` key from the container's JSON configuration.
2.  **Handle `unconfined`:** If the profile is set to `"unconfined"`, ensure that no `lxc.apparmor.profile` line is present in the container's `.conf` file.
3.  **Apply Profile:** If a specific profile is defined, idempotently set the `lxc.apparmor.profile` in the container's `.conf` file to the specified value.

## 4. Summary and Workflow

This new architecture provides a more robust, flexible, and transparent way to manage AppArmor profiles.

### Workflow Diagram:

```mermaid
graph TD
    A[phoenix setup] --> B[hypervisor-manager.sh];
    B --> C[hypervisor_feature_setup_apparmor.sh];
    C --> D[Copies all profiles from etc/apparmor/ to /etc/apparmor.d/];
    D --> E[Reloads AppArmor service];

    F[phoenix create <CTID>] --> G[lxc-manager.sh];
    G --> H[Reads apparmor_profile from phoenix_lxc_configs.json];
    H --> I{Profile defined?};
    I -- Yes --> J[Sets lxc.apparmor.profile in <CTID>.conf];
    I -- No/unconfined --> K[Ensures no lxc.apparmor.profile line exists];
