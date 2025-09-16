# vLLM Orchestration Refinement Plan

## 1. Introduction

This document outlines the plan to correct a logic error in the vLLM feature installation script and to streamline the container configuration by removing redundant feature definitions.

## 2. Phase 1: Script and Configuration Correction

### Steps:

1.  **Fix Git Logic in `phoenix_hypervisor_feature_install_vllm.sh`:**
    *   **Action:** Replace the `git pull` command with a more robust sequence of `git fetch` followed by `git checkout` to the known-good commit.
    *   **Rationale:** This will prevent failures when the repository is in a "detached HEAD" state.

2.  **Remove Redundant `nvidia` Feature:**
    *   **Action:** Modify `phoenix_lxc_configs.json` to remove the `nvidia` feature from the configurations for containers 950 and 951.
    *   **Rationale:** The `nvidia` feature is already inherited from the base template (901 -> 920), so specifying it again is unnecessary and potentially confusing.

## 3. Phase 2: Verification

### Steps:

1.  **Destroy and Re-deploy Container 950:**
    *   **Action:** Destroy the partially created container 950 to ensure a clean slate, then re-run the `phoenix_orchestrator.sh` script for CTID 950.
    *   **Rationale:** This will test our corrected script and configuration.

2.  **Verify Successful Deployment:**
    *   **Action:** Confirm that the orchestration completes without errors and that the vLLM service is running correctly in the new container.
    *   **Rationale:** This will validate our refined, template-based deployment model.