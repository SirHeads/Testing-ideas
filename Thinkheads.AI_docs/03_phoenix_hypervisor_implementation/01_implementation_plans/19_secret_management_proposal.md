---
title: Secret Management Proposal for Phoenix Hypervisor
summary: A proposal to implement a secure secret management strategy using a file-based, encrypted vault to eliminate hardcoded credentials and enhance security.
document_type: Implementation Plan
status: Proposed
version: 1.0.0
author: Roo
owner: Technical VP
tags:
  - Phoenix Hypervisor
  - Security
  - Secret Management
  - Architecture
review_cadence: Ad-Hoc
last_reviewed: 2025-09-30
---

# Proposal: Implementing a Secure Secret Management Strategy

## 1. Introduction

The discovery of a hardcoded password in the Samba setup script (`hypervisor_feature_setup_samba.sh`) highlights a critical security vulnerability in our current architecture. To protect sensitive information and adhere to security best practices, we must implement a robust and centralized secret management solution.

This document proposes the adoption of a file-based, encrypted vault for managing all secrets within the Phoenix Hypervisor ecosystem.

## 2. Current State Analysis

**Architecture:** Secrets, such as passwords and API tokens, are either hardcoded directly in scripts or omitted from configuration, requiring manual intervention.

**Strengths:**
*   **Simplicity (Deceptive):** Easy to implement in the short term.

**Weaknesses:**
*   **High Security Risk:** Storing secrets in plaintext, especially within a Git repository, is a major security flaw.
*   **Poor Maintainability:** Changing a secret requires finding and updating it in multiple places, which is error-prone.
*   **No Audit Trail:** There is no way to track who accessed or changed a secret.
*   **Incomplete Automation:** Manual steps are required to inject secrets, undermining our goal of a fully automated, idempotent system.

## 3. Proposed Architecture: Encrypted Secret Vault

I propose the use of a file-based, encrypted vault to store all secrets. Given our single-node, on-premise environment, a solution like `git-crypt` or a custom GPG-encrypted file provides a pragmatic balance of security and operational simplicity.

**Proposed Workflow:**

1.  **Create a Vault:** A dedicated, encrypted file (e.g., `secrets.json.gpg`) will be created to store all secrets as key-value pairs.
2.  **Encryption:** This file will be encrypted using a strong GPG key. The private key will be securely stored on the Proxmox host, and the public key can be shared with authorized developers.
3.  **Integration with Orchestrator:** The orchestration engine (ideally the proposed Python-based engine) will be responsible for:
    *   Decrypting the vault at runtime using the GPG key on the host.
    *   Injecting the secrets into the appropriate environment (e.g., as environment variables for scripts, or by placing them in temporary files with strict permissions).
4.  **Access Control:** Only the Proxmox host and authorized developers with the GPG key will be able to decrypt the secrets.

### 3.1. "After" Architecture Diagram

This diagram illustrates the proposed secret management workflow.

```mermaid
graph TD
    subgraph Development
        A[Developer] -- Encrypts/Edits --> B[secrets.json.gpg]
        B -- Commits to --> C[Git Repository]
    end

    subgraph Proxmox Host
        D[Orchestrator]
        E[GPG Private Key]
        F[Decrypted Secrets (In-Memory)]
    end

    subgraph Target Environment
        G[LXC Container / VM]
    end

    C -- Pulls --> B
    D -- Uses --> E
    D -- To Decrypt --> B
    B -- Yields --> F
    D -- Injects --> G

    style D fill:#f9f,stroke:#333,stroke-width:2px
    style E fill:#c99,stroke:#333,stroke-width:2px
```

## 4. Goals and Gains

### Goals

*   **Eliminate Hardcoded Secrets:** Remove all sensitive information from scripts and configuration files.
*   **Centralize Secret Management:** Provide a single, secure location for all secrets.
*   **Secure Storage:** Ensure that secrets are encrypted both at rest (in the Git repo) and in transit.
*   **Automate Secret Injection:** Integrate secret management seamlessly into the orchestration workflow.

### Gains

*   **Improved Security:** Drastically reduces the risk of credential exposure.
*   **Enhanced Maintainability:** Secrets can be updated in one place without code changes.
*   **Compliance and Auditing:** Provides a clear path toward tracking and managing access to sensitive information.
*   **Complete Automation:** Enables a fully hands-off, automated provisioning process.

## 5. Next Steps

If this proposal is approved, the immediate next steps would be:

1.  Generate a GPG key pair for the Phoenix Hypervisor.
2.  Create the initial `secrets.json.gpg` vault with the Samba password.
3.  Develop a proof-of-concept for decrypting and injecting this secret in the new orchestration engine.
4.  Scrub the existing codebase to identify and migrate all other hardcoded secrets.