---
title: 'Feature: vLLM'
summary: The `vllm` feature automates the complete setup of the vLLM inference engine from a pinned source commit, preparing a container to serve high-throughput large language models.
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
The `vllm` feature automates the complete setup of the vLLM (vLLM) inference engine from source within an LXC container. It prepares the container to serve high-throughput large language models by performing a series of critical steps, ensuring a reproducible and high-performance environment.

## Key Actions

1.  **Dependency Verification:** Verifies that the `nvidia` and `python_api_service` features are present and that `nvidia-smi` is functional.
2.  **Environment Setup:** Installs Python 3.11, build-essential tools, and creates an isolated Python virtual environment in `/opt/vllm`.
3.  **PyTorch Installation:** Installs a specific nightly build of PyTorch compatible with CUDA 12.1+.
4.  **vLLM Source Installation:** Clones the vLLM repository, checks out a specific, known-good commit, and builds and installs vLLM and its dependency FlashInfer from source.
5.  **Systemd Service Template:** Creates a generic systemd service file at `/etc/systemd/system/vllm_model_server.service` that can be used by application scripts to launch a model.
6.  **Idempotency:** The script checks for an existing vLLM installation in `/opt/vllm` and skips the installation if it's already present.

## Usage

This feature is applied to any container that will be used to host a vLLM-based inference server. It has a hard dependency on the `nvidia` and `python_api_service` features, which must be listed before it in the `features` array in the container's configuration.
