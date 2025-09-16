# Phoenix Hypervisor Unified Strategy

## 1. Executive Summary

This document outlines the new, unified architectural strategy for the Phoenix Hypervisor project. It addresses the root cause of the persistent `idmap` generation failure and defines a clear, professional-grade approach to users, permissions, and file access across the entire platform. This document supersedes all previous architectural markdown files.

## 2. `idmap` Root Cause Analysis

The root cause of the `idmap` generation failure is an overly restrictive AppArmor profile that prevents unprivileged containers from performing the necessary `mount` operations during startup. This blocks the container's startup sequence and interferes with the `idmap` process.

## 3. The New Unified Architecture

### 3.1. `idmap` Resolution

The AppArmor profile for unprivileged containers will be modified to allow the necessary `mount` operations. The `lxc-default-with-mounting` profile will be used as a base, and any additional required permissions will be added.

### 3.2. Unified User and Permissions Strategy

*   **Host Users:** A single, non-root user (`phoenix_admin`) will be created on the host with sudo privileges. This user will be responsible for all administrative tasks.
*   **Container Users:** All unprivileged containers will run as the `root` user inside the container, which will be mapped to a high-UID user on the host via the `idmap`.
*   **Shared Volume Ownership:** All shared volumes will be owned by the `phoenix_admin` user on the host. The `idmap` will be used to ensure that the `root` user inside the container has the necessary permissions to read and write to these volumes.

### 3.3. Simplified File Access Control

The `shared_volumes` section of the `phoenix_hypervisor_config.json` will be simplified. The `owner` property will be removed, and all volumes will be owned by the `phoenix_admin` user. The `apply_shared_volumes` function in `phoenix_orchestrator.sh` will be modified to set the correct ownership and permissions on all shared volumes based on the `idmap`.

## 4. Implementation Plan

1.  **AppArmor Profile:**
    *   Create a new AppArmor profile for unprivileged containers based on `lxc-default-with-mounting`.
    *   Modify the profile to allow the necessary `mount` operations.
    *   Update the `phoenix_orchestrator.sh` script to apply the new profile to all unprivileged containers.

2.  **User Management:**
    *   Modify the `hypervisor_feature_create_admin_user.sh` script to create the `phoenix_admin` user.
    *   Update the `phoenix_hypervisor_config.json` file to reflect the new username.

3.  **Shared Volumes:**
    *   Remove the `owner` property from the `shared_volumes` section of the `phoenix_hypervisor_config.json` file.
    *   Modify the `apply_shared_volumes` function in `phoenix_orchestrator.sh` to set the correct ownership and permissions on all shared volumes.