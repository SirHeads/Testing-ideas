# vLLM Implementation Comparison: Phoenix vs. External Research

This document compares our internal, automated vLLM setup (`phoenix_hypervisor_feature_install_vllm.sh`) with the manual, cutting-edge methods described in the provided external research for enabling vLLM on Blackwell GPUs.

## High-Level Comparison

| Feature / Aspect | External Research (Manual Build) | Our Current Implementation (Automated) | Analysis & Gap |
| :--- | :--- | :--- | :--- |
| **Installation Method** | **Build from Source** (Git clone) | **Pre-release Wheels** (`pip install --pre vllm`) | **Major Gap.** We are not building from source, which is the key requirement for Blackwell. |
| **PyTorch Version** | **PyTorch 2.9 Nightly** (`--pre`) | **PyTorch Test Build for cu128** (`--pre`) | **Close.** We are already using a forward-looking PyTorch version, but the research suggests the *nightly* channel is required, not the *test* channel. |
| **Dependency Handling** | `use_existing_torch.py` script | Standard `pip` dependency resolution | **Major Gap.** We are not using the critical script that resolves the PyTorch version conflict. |
| **Architecture Targeting** | `TORCH_CUDA_ARCH_LIST="12.0"` | `TORCH_CUDA_ARCH_LIST="12.0"` (in `systemd`) | **Aligned.** We are already setting this, but it's only applied at runtime, not during installation. |
| **Flash Attention** | `VLLM_FLASH_ATTN_VERSION=2` | Not explicitly set. | **Potential Gap.** Our installation may be failing if it defaults to FA3, which is unsupported. |
| **Automation** | Manual, step-by-step process | Fully automated via `phoenix-cli` | **Our Strength.** Our framework is designed for automation, which is a significant advantage. |
| **Configuration** | Manual CLI arguments | Declarative (`vllm_engine_config` in JSON) | **Our Strength.** Our declarative approach is more robust and reproducible. |
| **Security** | Not mentioned | Automated TLS certs via internal Step-CA | **Our Strength.** Our implementation is more secure out-of-the-box. |

## Detailed Analysis of Gaps

### 1. Installation Method: Pre-release Wheels vs. Building from Source

This is the most significant difference. Our current script, `phoenix_hypervisor_feature_install_vllm.sh`, uses `pip install --pre vllm`. This installs the latest available pre-compiled wheel from PyPI. The research makes it clear that **no pre-compiled wheels currently support the Blackwell (sm_120) architecture.**

*   **External Method:** Clones the `vllm` repository and runs `pip install -e .` to build it from the source code on the machine itself.
*   **Our Method:** Downloads a pre-built binary that lacks the necessary compiled kernels for our new GPUs.
*   **Conclusion:** This is the primary reason our vLLM feature is likely failing on the new hardware.

### 2. Dependency Handling: `use_existing_torch.py`

The external research identifies a "dependency deadlock" where vLLM's requirements specify `torch==2.8.0`, but Blackwell requires `torch>=2.9`. The key to resolving this is the `use_existing_torch.py` script.

*   **External Method:** Runs this script after cloning the repository and before building. This modifies the vLLM source to accept the newer, already-installed PyTorch nightly.
*   **Our Method:** We do not perform this step. Our `pip` installation attempts standard dependency resolution, which would fail when it sees the conflict between the hardware's requirement and the package's metadata.
*   **Conclusion:** This is the second critical missing piece in our installation logic.

### 3. Environment Variables During Build

The research emphasizes setting `TORCH_CUDA_ARCH_LIST` and `VLLM_FLASH_ATTN_VERSION` *before* the build process.

*   **External Method:** `export TORCH_CUDA_ARCH_LIST="12.0"` is set in the shell before `pip install`.
*   **Our Method:** We set `TORCH_CUDA_ARCH_LIST="12.0"` in the `systemd` service file (`phoenix_hypervisor_lxc_vllm.sh`). This is a **runtime** variable, not a **build-time** variable. The compiled kernels for the `sm_120` architecture are likely not being included in the wheel we are downloading.
*   **Conclusion:** We need to ensure these variables are present during the installation phase, not just at runtime.

## Our Strengths

Despite these gaps, our current implementation has several significant advantages that we should leverage:

*   **Automation Framework:** We don't need to manually run these steps. We can codify the source build process directly into our `phoenix_hypervisor_feature_install_vllm.sh` script.
*   **Declarative Configuration:** Our `vllm_engine_config` in the JSON file is a robust way to manage models. We can continue to use this to generate the final `systemd` service, regardless of the installation method.
*   **Security Integration:** Our automated TLS certificate provisioning is a feature the manual builds do not address and gives us a major advantage in terms of security and manageability.

## Path Forward

The path to enabling Blackwell support is clear. We need to adapt our `phoenix_hypervisor_feature_install_vllm.sh` script to incorporate the successful build-from-source method identified in the research, while retaining our automation and configuration strengths.