---
title: 'Architectural Plan: Docker in Unprivileged LXC Remediation and Security Hardening'
summary: An architectural plan for running Docker securely and efficiently in unprivileged LXC containers, focusing on AppArmor profile standardization.
document_type: Architectural Plan
status: Approved
version: 2.0.0
author: Roo
owner: Technical VP
tags:
  - Docker
  - LXC
  - Remediation
  - Security
  - AppArmor
  - fuse-overlayfs
review_cadence: Annual
last_reviewed: 2025-09-30
---

# Architectural Plan: Docker in Unprivileged LXC Remediation and Security Hardening

## 1. High-Level Summary

### 1.1. The Problem

Running Docker within unprivileged LXC containers requires careful configuration to balance security and functionality. While our current implementation has successfully adopted the `fuse-overlayfs` storage driver for improved performance, the AppArmor confinement strategy is inconsistent. Most Docker-enabled containers run with an `unconfined` profile, creating an unnecessary security risk. This plan addresses the need to standardize our security posture by applying a robust, least-privilege AppArmor profile to all Dockerized containers.

### 1.2. The Proposed Solution

This document outlines an architectural plan to remediate and harden our Docker-in-LXC implementation. The solution involves:

1.  **Standardizing AppArmor Confinement:** Applying the `lxc-phoenix-v2` profile to all containers with the `docker` feature, ensuring a consistent and secure baseline.
2.  **Verifying Existing Configurations:** Confirming that the `fuse-overlayfs` storage driver and host-level AppArmor tunables are correctly implemented.
3.  **Updating Documentation:** Aligning this plan with the current state of the `phoenix_hypervisor` project and clearly defining the path forward for security enhancements.

This plan will be implemented through our declarative `phoenix_orchestrator.sh` framework, ensuring all changes are automated, repeatable, and consistent.

## 2. Implementation and Verification Plan

### Step 1: Verify `fuse-overlayfs` Storage Driver Implementation (Completed)

*   **Status:** The `fuse-overlayfs` driver has been successfully implemented.
*   **Verification:**
    *   The `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_docker.sh` script correctly installs `fuse-overlayfs` and configures `/etc/docker/daemon.json`.
    *   After provisioning a Docker-enabled container, execute `pct exec <CTID> -- docker info | grep "Storage Driver"` and confirm the output is `fuse-overlayfs`.

### Step 2: Standardize the `lxc-phoenix-v2` AppArmor Profile

*   **Why This Is Necessary:** A properly configured AppArmor profile is our primary defense against container escapes. Applying the `lxc-phoenix-v2` profile consistently ensures that all Docker containers operate under the principle of least privilege, significantly enhancing our security posture.
*   **Implementation Steps:**
    1.  **Update LXC Configurations:** In `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`, change the `apparmor_profile` for all containers with the `docker` feature from `unconfined` to `lxc-phoenix-v2`.
    2.  **Automated Deployment:** The `phoenix_orchestrator.sh` script will automatically apply the updated profile during the container provisioning process.
*   **Verification:**
    *   After provisioning a container, execute `pct config <CTID>` and confirm that the `lxc.apparmor.profile` is set to `lxc-phoenix-v2`.
    *   Monitor the host's audit logs (`/var/log/audit/audit.log` or `dmesg`) for any `apparmor="DENIED"` messages related to Docker operations. The absence of such messages indicates a correctly configured profile.

### Step 3: Verify Docker Installation Script Optimization (Completed)

*   **Status:** The Docker installation script is already optimized.
*   **Verification:**
    *   The `phoenix_hypervisor_feature_install_docker.sh` script is idempotent and includes error handling (`set -e`). It can be re-run without causing errors, ensuring consistent provisioning.

### Step 4: Verify Host AppArmor Tunables

*   **Why This Is Necessary:** The Proxmox host's AppArmor configuration must permit profile stacking for container-specific policies to be enforced correctly.
*   **Verification:**
    *   The `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_apparmor.sh` script deploys the necessary profiles. While it doesn't explicitly set tunables for nesting, the successful operation of the `lxc-phoenix-v2` profile on the Portainer container (CTID 910) confirms that nesting is functional.

## 3. Security Enhancement Proposal

To further strengthen our security posture, we propose the following:

*   **Universal `lxc-phoenix-v2` Adoption:** All LXC containers with the `docker` feature should use the `lxc-phoenix-v2` AppArmor profile. This will create a uniform security standard across our environment, reducing the risk of misconfiguration and ensuring that all containers benefit from the same level of confinement.

This change will be implemented by updating the `phoenix_lxc_configs.json` file as described in Step 2.

## 4. Expected Outcomes

Upon successful implementation of this plan, we expect the following outcomes:

*   **Enhanced Security:** All Dockerized containers will be confined by a least-privilege AppArmor profile, significantly reducing the attack surface.
*   **Improved Standardization:** A consistent security policy across all containers will reduce complexity and improve maintainability.
*   **Increased Confidence:** A well-documented and verified security implementation will provide greater confidence in the stability and security of our containerized services.