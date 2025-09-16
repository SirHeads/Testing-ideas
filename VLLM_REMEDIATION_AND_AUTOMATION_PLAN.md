# vLLM Remediation and Automation Plan

## 1. Introduction

This document outlines the plan to verify the exact conditions that led to the successful launch of the vLLM service in container 950 and to integrate these findings into the `phoenix_orchestrator.sh` deployment script.

## 2. Phase 1: Verification of the Working State

The goal of this phase is to confirm the precise configuration and software versions that are currently working in container 950.

### Steps:

1.  **Confirm vLLM Version:**
    *   **Action:** Check the installed vLLM version in container 950 to ensure it matches the known-good commit from container 951.
    *   **Rationale:** This verifies that our reinstallation was successful and is the foundation of the fix.

2.  **Confirm `ninja-build` Installation:**
    *   **Action:** Verify that the `ninja-build` package is installed and the `ninja` executable is available in the system's PATH.
    *   **Rationale:** This confirms the final dependency fix that resolved the JIT compilation error.

3.  **Document the Working Startup Command:**
    *   **Action:** Identify the exact command that is currently running the successful vLLM process.
    *   **Rationale:** This command, with its specific parameters, will be the basis for the automated script.

## 3. Phase 2: Automation in `phoenix_orchestrator.sh`

The goal of this phase is to modify the orchestration script to reliably reproduce the working state in a new container.

### Steps:

1.  **Analyze `phoenix_orchestrator.sh`:**
    *   **Action:** Read the contents of the `phoenix_orchestrator.sh` and any relevant sub-scripts (e.g., `phoenix_hypervisor_lxc_950.sh`) to understand the current vLLM deployment process.
    *   **Rationale:** We need to identify where the vLLM installation and service startup are handled.

2.  **Modify the Script to Install `ninja-build`:**
    *   **Action:** Add a step to the script to install the `ninja-build` package using `apt-get`.
    *   **Rationale:** This ensures the critical build dependency is always present.

3.  **Modify the Script to Use the Correct vLLM Commit:**
    *   **Action:** Add steps to the script to clone the vLLM repository and check out the specific, known-good commit hash (`5bcc153d7bf69ef34bc5788a33f60f1792cf2861`).
    *   **Rationale:** This prevents the deployment from accidentally using a broken or unstable development build.

4.  **Modify the Script to Use the Correct Startup Command:**
    *   **Action:** Update the script to use the exact startup command and parameters that we have verified to be working.
    *   **Rationale:** This ensures the service is launched with the correct configuration.

## 4. Phase 3: Final Verification

The goal of this phase is to test the modified orchestration script by deploying a new container.

### Steps:

1.  **Deploy a New vLLM Container:**
    *   **Action:** Use the modified `phoenix_orchestrator.sh` to create and configure a new vLLM container (e.g., 952).
    *   **Rationale:** This is the ultimate test of our automated procedure.

2.  **Verify the New Container:**
    *   **Action:** Check that the vLLM service starts successfully in the new container without any manual intervention.
    *   **Rationale:** This confirms that our automation is robust and the issue is permanently resolved.