---
title: 'Feature: vLLM'
summary: The `vllm` feature installs the vLLM inference engine and its dependencies (PyTorch, FlashInfer), preparing a container for high-throughput model serving, including large language models and embedding models. It works in conjunction with an application script that handles the dynamic service configuration.
document_type: "Feature Summary"
status: "Approved"
version: "1.0.0"
author: "Phoenix Hypervisor Team"
owner: "Developer"
tags:
  - "vLLM"
  - "LLM Inference"
  - "AI"
  - "Machine Learning"
  - "Model Serving"
  - "Python"
review_cadence: "Annual"
last_reviewed: "2025-09-23"
---
The `vllm` feature is responsible for installing the vLLM inference engine and its required dependencies into a container. It ensures that the correct versions of vLLM, PyTorch, and FlashInfer are installed in an isolated Python virtual environment, preparing the container for an application script to deploy a model.

## Key Actions

1.  **Dependency Verification:** Verifies that the `nvidia` feature is present and that `nvidia-smi` is functional.
2.  **Environment Setup:** Installs Python 3.11, build-essential tools, and creates an isolated Python virtual environment in `/opt/vllm`.
3.  **PyTorch Installation:** Installs a specific nightly build of PyTorch compatible with the latest CUDA version.
4.  **FlashInfer Installation:** Installs a pinned version of the FlashInfer library from source for optimized performance.
5.  **vLLM Installation:** Installs a specific version of vLLM from a pip wheel.
6.  **Idempotency:** The script checks for an existing vLLM installation in `/opt/vllm` and skips the installation if it's already present.

## Usage

This feature is applied to any container that will be used to host a vLLM-based inference server. It has a hard dependency on the `nvidia` and `python_api_service` features, which must be listed before it in the `features` array in the container's configuration.

### Usage Example: Embedding Models

The `vllm` feature is also used to power embedding models. A prime example is its use in LXC 801, which hosts the `granite-embedding` model. This setup provides a high-performance embedding service for various AI applications.
