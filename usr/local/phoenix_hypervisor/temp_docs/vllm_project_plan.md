# Project Plan: vLLM FP8 Optimization for Blackwell Architecture

**Version**: 2.0  
**Date**: October 1, 2025  
**Author**: Roo, in collaboration with the Phoenix Hypervisor Team  
**Status**: Finalized Plan

## 1. Executive Summary

This document outlines the official project plan to enable high-performance 8-bit FP8 inference for vLLM on our NVIDIA RTX 5060 Ti (Blackwell) GPUs. This initiative moves beyond the initial consultant proposal to create a solution that is fully integrated with the `phoenix_hypervisor`'s core architectural principles.

The project will involve creating a new, dedicated vLLM template container (CTID 921), updating key software dependencies (vLLM, PyTorch, FlashInfer), and enhancing our declarative configuration model in `phoenix_lxc_configs.json` to be more structured and robust. All changes will be implemented in a modular, idempotent, and declarative manner.

## 2. Guiding Principles

All work undertaken in this project will strictly adhere to the foundational principles of the Phoenix Hypervisor architecture:

*   **Declarative State**: The desired state of all components will be defined in `phoenix_lxc_configs.json`. The system will converge to match this state.
*   **Idempotency**: All scripts and operations will be designed to be safely re-runnable without causing unintended side effects.
*   **Modularity**: Functionality will be encapsulated within the appropriate scripts (feature vs. application), maintaining a clean separation of concerns.

## 3. Architectural Decisions

Based on our review, we have established the following architectural approach:

### 3.1. New FP8 Template (CTID 921)

To avoid disrupting existing, stable AWQ workloads (CTIDs 950, 951), we will **not** modify the current vLLM template (920). Instead, we will create a new, dedicated container for FP8 experimentation and deployment:

*   **CTID**: `921`
*   **Name**: `Template-VLLM-FP8`
*   **Clone Source**: It will be cloned from `901` (`Template-GPU`) to ensure it inherits the correct base setup and host-side NVIDIA driver integration without the legacy vLLM installation.
*   **Purpose**: This provides a clean, isolated environment for the new dependency stack and FP8 configuration.

### 3.2. vLLM Installation Strategy

We will adopt a "pip wheel first" strategy to simplify dependency management, with a clear fallback plan.

*   **Primary Method**: The `phoenix_hypervisor_feature_install_vllm.sh` script will be modified to install vLLM using a specific pip wheel version (e.g., `vllm==0.10.2`).
*   **Contingency Plan**: If the pip wheel proves unstable or lacks necessary optimizations for our specific environment, the plan includes reverting to a source code build from a new, known-good commit hash.

### 3.3. Declarative Environment Management

We will **not** modify the global `/etc/environment` file. Instead, CUDA environment variables will be managed declaratively and applied at runtime.

*   **Implementation**: The `phoenix_hypervisor_lxc_vllm.sh` application script will be responsible for dynamically generating the `vllm_model_server.service` systemd unit file. To prevent conflicts with user-level environment variables, the script will explicitly unset potentially conflicting variables before setting the correct ones for the service.

## 4. Proposed `phoenix_lxc_configs.json` Schema Enhancement

To better align with vLLM's capabilities and improve the clarity of our configurations, we will introduce a new, structured object to replace the flat `vllm_parameters` and `vllm_args` keys. This new structure mirrors the official vLLM Engine Arguments.

The `phoenix_hypervisor_lxc_vllm.sh` script will be updated to parse this object and construct the final CLI arguments for the vLLM server.

**Example of the new schema for CTID 921:**

```json
"921": {
    "name": "Template-VLLM-FP8",
    "clone_from_ctid": "901",
    "features": ["nvidia", "vllm"],
    "application_script": "phoenix_hypervisor_lxc_vllm.sh",
    "vllm_engine_config": {
        "ModelConfig": {
            "model": "meta-llama/Llama-3.2-3B-Instruct",
            "trust_remote_code": true,
            "dtype": "auto",
            "max_model_len": 8192
        },
        "CacheConfig": {
            "quantization": "fp8",
            "kv_cache_dtype": "fp8",
            "gpu_memory_utilization": 0.90
        },
        "ParallelConfig": {
            "tensor_parallel_size": 2
        },
        "ServerConfig": {
            "host": "0.0.0.0",
            "port": 8000,
            "served_model_name": "llama-3.2-3b-fp8"
        }
    }
}
```

## 5. Implementation Plan

### Phase 1: Configuration (`phoenix_lxc_configs.json`)

1.  **Define New Container**: Add a new entry for CTID `921` in `phoenix_lxc_configs.json`.
    *   Set `name` to `Template-VLLM-FP8`.
    *   Set `clone_from_ctid` to `901`.
    *   Assign a unique IP address and MAC address.
    *   Include `nvidia` and `vllm` in the `features` array.
2.  **Implement New Schema**: For CTID `921`, add the `vllm_engine_config` object as defined in section 4.

### Phase 2: Feature Script Updates (`phoenix_hypervisor_feature_install_vllm.sh`)

1.  **Update PyTorch**: Modify the `pip install` command to use the `cu128` nightly index for full Blackwell compatibility.
2.  **Update FlashInfer**: Modify the git clone and install process to check out and install the specified `v0.3.1` tag. The clone command will be made idempotent (`|| true`). Add a post-install verification step to ensure the correct version was installed.
3.  **Update vLLM Installation**: Replace the entire `git clone` and `pip install -e` logic for vLLM with a single command: `pip install vllm==0.10.2`.
4.  **Remove Systemd Logic**: Delete the `create_vllm_systemd_service` function entirely. Its responsibility will be moved to the application script.

### Phase 3: Application Script Enhancement (`phoenix_hypervisor_lxc_vllm.sh`)

1.  **Add Parser Logic**: Implement shell functions (using `jq`) to parse the `vllm_engine_config` object from `phoenix_lxc_configs.json` for the given CTID.
2.  **Add Systemd Generator**: Create a new function that dynamically generates the content for `vllm_model_server.service`.
    *   This function will first write `Environment=` lines to unset `CUDA_HOME` and `LD_LIBRARY_PATH`.
    *   It will then write the necessary CUDA `Environment=` lines to set the correct paths.
    *   It will add `Environment="VLLM_USE_FLASHINFER_SAMPLER=1"`.
    *   It will iterate through the parsed `vllm_engine_config` object and convert each key-value pair into a valid vLLM command-line argument (e.g., `--tensor-parallel-size 2`).
3.  **Implement Service Deployment**: The script will:
    *   Write the generated service content to a temporary file on the hypervisor.
    *   Use `pct push` to place the file at `/etc/systemd/system/vllm_model_server.service` inside the container.
    *   Execute `pct exec` to run `systemctl daemon-reload` and `systemctl enable --now vllm_model_server.service`.

## 6. Testing and Validation

1.  **Build Container**: Run `phoenix create 921`.
2.  **Verify Dependencies**:
    *   `pct exec 921 -- /opt/vllm/bin/python -c 'import vllm; print(vllm.__version__)'` (Should output `0.10.2`).
    *   `pct exec 921 -- /opt/vllm/bin/python -c 'import torch; print(torch.version.cuda)'` (Should output `12.8`).
    *   `pct exec 921 -- /opt/vllm/bin/python -c 'import flashinfer; print(flashinfer.__version__)'` (Should output `0.3.1`).
3.  **Verify Service**:
    *   `pct exec 921 -- systemctl status vllm_model_server.service`.
    *   Check the service logs for errors and for the "FlashInfer kernel loaded" message: `pct exec 921 -- journalctl -u vllm_model_server.service`.
4.  **Integration Test**:
    *   Send a request to the model endpoint: `curl http://<IP_of_921>:8000/v1/models`.
    *   Perform a test inference to confirm FP8 is working correctly.
5.  **Benchmark**: Compare tokens/sec with and without `VLLM_USE_FLASHINFER_SAMPLER=1` (expect +20% on FP8).

## 7. Fallback Plan

If FlashInfer `v0.3.1` causes instability or "unsupported kernel" errors in the vLLM logs, the following steps will be taken:
1.  Modify `phoenix_hypervisor_feature_install_vllm.sh` to check out a more stable tag (e.g., `v0.3.0`).
2.  If issues persist, set `VLLM_USE_FLASHINFER_SAMPLER=0` in the generated systemd service to use vLLM's internal sampler and re-run tests.