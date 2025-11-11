# Summary of External Research on vLLM for Blackwell GPUs

This document summarizes the key findings from the provided online sources regarding the setup and performance of vLLM on NVIDIA's Blackwell architecture (sm_120), specifically the RTX 50-series GPUs.

## Key Challenge: The Dependency Deadlock

The core problem identified by both sources is a "dependency deadlock" that makes standard installations fail:

1.  **Hardware Requirement:** Blackwell GPUs (sm_120) require a minimum of CUDA 12.8.
2.  **PyTorch Gap:** The vLLM nightly builds have a dependency on `torch==2.8.0`, but there are no official or available PyTorch 2.8.x wheels compiled for CUDA 12.8 (`cu128`).
3.  **The Squeeze:** This forces users into a situation where the hardware requires a newer PyTorch version (>=2.9) than the vLLM software officially supports in its dependency tree.

## The Solution: Build from Source with PyTorch Nightly

Both sources arrive at the same successful solution, bypassing the dependency deadlock by building vLLM from source against a newer, unreleased version of PyTorch.

### Core Components of the Successful Build:

*   **PyTorch Version:** A nightly build of PyTorch 2.9.x for CUDA 12.8 (e.g., `torch==2.9.0.dev20250831+cu128`). This is the only version that provides the necessary `sm_120` support.
*   **Build from Source:** Cloning the `vllm` repository from GitHub and building it locally is mandatory. Pre-built wheels from PyPI will not work.
*   **`use_existing_torch.py`:** Both sources highlight the critical importance of running this script. It appears to modify the vLLM dependency files to accept the already-installed PyTorch nightly version, resolving the conflict.
*   **Environment Variables:** Specific environment variables are required to target the Blackwell architecture correctly during compilation:
    *   `TORCH_CUDA_ARCH_LIST="12.0"`: This explicitly tells the compiler to build for the Blackwell `sm_120` architecture. The second source also found `10.0` was needed, suggesting some backward compatibility components might be required.
    *   `VLLM_FLASH_ATTN_VERSION=2`: Flash Attention 3 is not yet supported on Blackwell, so the build must be forced to use version 2.
    *   `MAX_JOBS`: Limiting the number of parallel compilation jobs is necessary to avoid excessive memory consumption (e.g., `MAX_JOBS=6` or `MAX_JOBS=8`).

## Performance Insights (from Source 1)

*   **Impressive Speed:** The RTX 5090 achieves over 290 tokens/second on a Qwen2.5-7B model, demonstrating enterprise-grade performance.
*   **High VRAM Usage:** The current builds are memory-aggressive, with a 7B model consuming 31GB of VRAM due to KV cache pre-allocation.
*   **Optimization:** The system uses CUDA Graphs and `torch.compile` to optimize performance over time, with inference speed increasing after the initial "cold start."

## Comparison with Alternatives

The first source provides a valuable comparison with other inference engines:

*   **llama.cpp:** The most reliable and easiest to set up on Blackwell. Recommended as the first choice for most users.
*   **TensorRT-LLM:** Offers the highest potential performance but requires a complex, NVIDIA-specific setup.
*   **Ollama:** Works reliably and is easy to install, but offers moderate performance. A good fallback option.

## Key Takeaways & Recommendations for Developers

*   **Avoid Pre-built Wheels:** They are guaranteed to fail for Blackwell GPUs at this time.
*   **Embrace Source Builds:** This is the only viable path to enabling vLLM on the latest hardware.
*   **Dependency Management is Key:** The combination of `uv` for environment management, a specific PyTorch nightly, and the `use_existing_torch.py` script is the formula for success.
*   **Documentation is Lagging:** The community is currently ahead of the official documentation in solving these cutting-edge hardware issues.