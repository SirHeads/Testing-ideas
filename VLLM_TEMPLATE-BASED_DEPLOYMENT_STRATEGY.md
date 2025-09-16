# vLLM Template-Based Deployment Strategy

## 1. Introduction

This document outlines a new strategy for deploying vLLM containers. The current model, where each container builds its own environment from scratch, is slow and prone to inconsistencies. This plan details a transition to a template-based model, where a "golden" template container (CTID 920) is fully provisioned with a known-good vLLM environment, and new containers (e.g., 950, 951) are created as lightweight clones of this template.

## 2. Phase 1: Template Hardening (CTID 920)

The goal of this phase is to ensure that the template container (920) contains the complete, correct, and verified vLLM environment.

### Steps:

1.  **Full vLLM Installation in Template:**
    *   **Action:** Execute the `phoenix_hypervisor_feature_install_vllm.sh` script (with our recent fixes) directly on the template container (920).
    *   **Rationale:** This will install the correct vLLM build, `ninja-build`, and all other dependencies into the template itself.

2.  **Create a "Golden" Snapshot:**
    *   **Action:** After the installation is complete and verified, create a new, versioned snapshot of the template container (e.g., `vllm-base-snapshot-v2`).
    *   **Rationale:** This snapshot captures the complete, working environment and serves as the basis for all future clones.

## 3. Phase 2: Streamlining the Orchestration Logic

The goal of this phase is to modify the orchestration scripts to leverage the new "golden" template and eliminate redundant build steps.

### Steps:

1.  **Update `phoenix_lxc_configs.json`:**
    *   **Action:** Modify the configuration for containers 950 and 951 to use the new snapshot (`vllm-base-snapshot-v2`) as their clone source.
    *   **Rationale:** This directs the orchestrator to use our new, fully-provisioned template.

2.  **Refactor `phoenix_hypervisor_feature_install_vllm.sh`:**
    *   **Action:** Modify this script to be "aware" of the template. When run on a cloned container, it should skip the entire installation process (cloning, building, etc.) and simply perform a quick verification to ensure the environment is intact.
    *   **Rationale:** This dramatically speeds up the deployment of new containers and makes the process more robust.

3.  **Refactor `phoenix_hypervisor_lxc_950.sh` (and similar scripts):**
    *   **Action:** This script's primary responsibility will be to configure and start the `systemd` service with the correct model and parameters for that specific container. The environment verification steps can be streamlined, as the environment is guaranteed by the template.
    *   **Rationale:** This separates the concerns of environment creation (template) and service configuration (application script).

## 4. Phase 3: Verification

The goal of this phase is to test the new, streamlined deployment process.

### Steps:

1.  **Deploy a New Container from the Golden Template:**
    *   **Action:** Use the modified `phoenix_orchestrator.sh` to deploy a new container (e.g., 950) from the new snapshot.
    *   **Rationale:** This will test the end-to-end process.

2.  **Verify Performance and Functionality:**
    *   **Action:** Confirm that the new container starts much faster than before and that the vLLM service is running correctly with the correct model.
    *   **Rationale:** This validates the benefits of our new, template-based architecture.