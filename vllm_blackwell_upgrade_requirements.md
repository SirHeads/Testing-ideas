# Project Requirements: vLLM Blackwell GPU Upgrade

**Author:** Roo
**Version:** 1.0 (Final)

## 1. Background & Problem Statement

The Phoenix Hypervisor platform's vLLM feature is a critical component for serving large language models. Our current implementation, while automated and robust, relies on pre-compiled vLLM wheels. New NVIDIA Blackwell GPUs (sm_120 architecture), such as the RTX 50-series, require CUDA 12.8+ and a version of PyTorch (2.9+) that is not supported by any available pre-compiled vLLM wheels.

This creates a "dependency deadlock" where our existing automated installation process (`phoenix_hypervisor_feature_install_vllm.sh`) will fail on any LXC container equipped with a Blackwell-series GPU. The goal of this project is to upgrade our installation process to fully support this new hardware.

## 2. Project Goals & Scope

### 2.1. In-Scope Goals

*   **Enable Blackwell Support:** The primary goal is to successfully and automatically install a functional vLLM environment in an LXC container that has a Blackwell (sm_120) GPU passed through to it.
*   **Adopt Build-from-Source Method:** The vLLM installation process must be modified to build vLLM from its source code, rather than relying on pre-compiled wheels.
*   **Retain Automation:** The entire installation process must remain fully automated and integrated within the existing `phoenix-cli` framework. A user should be able to provision a new vLLM container on Blackwell hardware with a single `phoenix create` command.
*   **Maintain Declarative Configuration:** The system must continue to use the `vllm_engine_config` object in `phoenix_lxc_configs.json` to define and launch models. The installation method should be transparent to the end-user.
*   **Preserve Security:** The new installation process must continue to integrate with our internal Step-CA to provide automated TLS certificates for each vLLM service.

### 2.2. Out-of-Scope

*   **Changes to the Application Runner:** This project will focus on the *installation* script (`phoenix_hypervisor_feature_install_vllm.sh`). The application runner script (`phoenix_hypervisor_lxc_vllm.sh`) should require minimal to no changes.
*   **Modifying the Core `phoenix-cli`:** The changes should be contained within the vLLM feature script.

## 3. Technical Requirements

Based on the initial analysis, the new installation process must perform the following steps:

1.  **Install PyTorch Nightly:** The script must install a nightly build of PyTorch 2.9+ for CUDA 12.8 (e.g., from the `https://download.pytorch.org/whl/nightly/cu128` index).
2.  **Clone vLLM Source:** The script must clone the vLLM repository from GitHub.
3.  **Set Build-Time Environment Variables:** The script must `export` the following variables before initiating the build:
    *   `TORCH_CUDA_ARCH_LIST="12.0"` (and potentially `10.0`)
    *   `VLLM_FLASH_ATTN_VERSION=2`
    *   `MAX_JOBS` (to a reasonable value to manage memory)
4.  **Run Dependency Resolution Script:** The script must execute the `use_existing_torch.py` script to align vLLM's dependencies with the installed PyTorch nightly.
5.  **Install Build Dependencies:** The script must install the necessary build requirements (e.g., from `requirements/build.txt`).
6.  **Compile and Install:** The script must compile and install vLLM using `pip install --no-build-isolation -e .`.
7.  **Verification:** The script should conclude by verifying that the installation was successful (e.g., by checking `vllm --version`).

## 4. Implementation Decisions

### 4.1. Source Code Management

The project will follow a two-phased approach:
*   **Phase 1 (Development):** The installation script will clone the `main` branch of the vLLM repository to ensure we are working with the latest code.
*   **Phase 2 (Stabilization):** Once a stable and functional build is achieved, the script will be updated to clone from a specific, known-good commit hash. This will ensure reproducible and reliable builds in the future. A variable for this commit hash will be added to the script for easy management.

### 4.2. GPU Architecture Handling

*   **Decision:** The new build-from-source method will become the standard installation path for all GPUs. The existing method of installing from a pre-compiled wheel will be removed to simplify the script and unify the process.

### 4.3. Build Artifacts

*   **Decision:** No special cleanup of build artifacts (e.g., the cloned repository) is required. These artifacts will be contained within the LXC container and will be automatically removed if the container is ever destroyed with the `phoenix delete` command.