# NVIDIA and CUDA Installation Consolidation Plan

## 1. Objective

The goal of this plan is to establish a single, authoritative source of documentation for the entire NVIDIA and CUDA installation process, covering both the Proxmox hypervisor and the LXC containers. This consolidated documentation will then serve as the definitive guide for identifying and resolving the persistent failures in the current installation scripts.

## 2. Guiding Principles

The final implementation must adhere to the following architectural principles:

-   **Single Source of Truth:** The NVIDIA driver version and `.run` file URL specified in the JSON configuration files are authoritative.
-   **Idempotency:** All installation scripts must be safely re-runnable without causing errors or unintended side effects.
-   **Efficiency:** Leverage a templating and cloning strategy to minimize redundant, time-consuming installations in derivative containers.
-   **Consistency:** The user-space driver version inside the LXC containers must precisely match the kernel driver version on the hypervisor.

## 3. Project Phases

### Phase 1: Documentation Consolidation & Strategy Definition

This phase focuses on creating the ideal documentation state, which will become the blueprint for the implementation.

**Action Items:**

1.  **Delete Obsolete Documentation:**
    -   Command: `rm nvidia_native_install_plan.md`
    -   Reasoning: This document proposes an `apt`-based installation, which contradicts the established architecture centered around the NVIDIA `.run` file.

2.  **Identify and Review Existing Documentation:**
    -   Conduct a thorough review of all existing project documents related to NVIDIA, GPU, and CUDA to synthesize a complete understanding of the current state. Key documents include:
        -   `usr/local/phoenix_hypervisor/project_documents/feature_nvidia_summary.md`
        -   `nvidia_hypervisor_vs_lxc_installation_analysis.md`
        -   `lxc_nvidia_passthrough_remediation_plan.md`
        -   `lxc_nvidia_timing_fix_plan.md`
        -   `nvidia_driver_cuda_install_plan.md`

3.  **Create the Authoritative Installation Guide:**
    -   Create a new document: `NVIDIA_CUDA_Installation_Guide.md`.
    -   This guide will detail the end-to-end process, including:
        -   **Hypervisor Setup (`--setup-hypervisor`):**
            -   Downloading the NVIDIA `.run` file from the URL in the configuration.
            -   Caching the `.run` file (e.g., in `/usr/local/phoenix_hypervisor/cache`) for subsequent use by LXC containers.
            -   Executing the `.run` file with flags appropriate for a full host-level installation (including the kernel module).
            -   Configuring the system-wide CUDA `apt` repository.
        -   **LXC Container Template Setup (`--LetsGo`):**
            -   **GPU Passthrough:** Modifying the container's `.conf` file to mount `/dev/nvidia*` devices and set `cgroup2` permissions based on the `gpu_assignment` configuration.
            -   **Driver Installation:** Pushing the cached `.run` file into the container and executing it with user-space-only flags (`--no-kernel-module`, etc.).
            -   **CUDA Installation:** Configuring the CUDA `apt` repository inside the Ubuntu 24.04 container and installing the `cuda-toolkit-12-8` package.
            -   **Verification:** Running `nvidia-smi` and `nvcc --version` to confirm success.

### Phase 2: Implementation Remediation

With the `NVIDIA_CUDA_Installation_Guide.md` as a reference, we will systematically correct the installation scripts.

**Action Items:**

1.  **Code Review:** Perform a line-by-line review of `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_install_nvidia.sh` and `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_nvidia.sh`.
2.  **Identify Discrepancies:** Create a list of all deviations between the scripts and the new guide. The current failure in `ensure_nvidia_repo_is_configured` is the first item on this list.
3.  **Implement Fixes:** Apply targeted changes to the scripts to bring them into alignment with the documentation. This will be done in a separate, focused effort after the documentation is approved.

### Phase 3: Validation

This phase will confirm that the remediated scripts function correctly.

**Action Items:**

1.  **Execute Orchestrator:** Run ` /usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh` to recreate the container templates (900, 901, 902, 903).
2.  **Verify Fixes:** For each container, manually execute the following commands to confirm the `apt` repository conflict is resolved and all components are functional:
    -   `apt-get update`
    -   `nvidia-smi`
    -   `nvcc --version`