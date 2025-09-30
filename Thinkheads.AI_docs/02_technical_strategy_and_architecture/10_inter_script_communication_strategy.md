---
title: Inter-Script Communication Strategy
summary: A strategy for passing structured configuration data between the phoenix_orchestrator.sh script and its sub-scripts, recommending the use of standard input for optimal decoupling.
document_type: Technical Strategy
status: Partially Implemented
version: 1.1.0
author: Roo
owner: Technical VP
tags:
  - Inter-Script Communication
  - Shell Scripting
  - JSON
  - stdin
  - Orchestration
  - Decoupling
review_cadence: Annual
last_reviewed: 2025-09-30
---

# Inter-Script Communication Strategy for Phoenix Hypervisor

**Author:** Roo, Architect
**Version:** 1.1.0
**Date:** 2025-09-30

## 1. Problem Statement

The `phoenix_orchestrator.sh` script, which serves as the central controller for the Phoenix Hypervisor framework, needs to pass structured configuration data to specialized sub-scripts. A key example is providing the `.zfs` configuration object from the master `phoenix_hypervisor_config.json` file to the `hypervisor_feature_setup_zfs.sh` script.

The primary challenge is to establish a communication pattern that is robust, maintainable, and aligns with our architectural principle of loose coupling between the orchestrator and its modules.

## 2. Analysis of Requirements

The ideal solution must adhere to the following principles:

*   **Decoupling:** The orchestrator and sub-scripts should be loosely coupled. Sub-scripts should not have intimate knowledge of the master configuration file's structure.
*   **Clarity:** The flow of data from the orchestrator to the sub-script should be explicit and easy to follow.
*   **Robustness:** The mechanism must be reliable and handle potential errors gracefully.
*   **Security:** The method should not expose sensitive configuration data unnecessarily.
*   **Maintainability:** The solution should be easy for developers to understand, modify, and debug.
*   **Testability:** Sub-scripts should be easily testable in isolation.

## 3. Current Implementation Status

As of the last review, the implementation is in a transitional state:

*   **`hypervisor_feature_setup_zfs.sh` (Sub-script):** This script has been successfully refactored. It now correctly handles reading configuration data from `stdin` when the `--config -` argument is used, aligning with the recommended strategy.
*   **`phoenix_orchestrator.sh` (Orchestrator):** This script has **not** yet been updated. It currently passes the full path to the `phoenix_hypervisor_config.json` file to the sub-script.

This discrepancy means the system is functional but does not yet benefit from the improved decoupling and testability of the recommended approach. The strategy outlined below remains the target state.

## 4. Evaluated Solutions

### Option 1: Temporary Files (Tactical Fix)

This approach involves the orchestrator extracting the relevant JSON section into a temporary file and passing the path of that file to the sub-script.

*   **Pros:** Simple and quick to implement.
*   **Cons:** Introduces state management overhead (cleanup), filesystem clutter, and is not an elegant architectural pattern.

### Option 2: Environment Variables

The orchestrator could export the JSON data as an environment variable.

*   **Pros:** Avoids filesystem operations.
*   **Cons:** Clumsy for structured data, subject to size limitations, poses a security risk by exposing data to other processes, and offers poor readability for debugging.

### Option 3: Pass Full Config Path (Current Method)

The orchestrator passes the path to the main `phoenix_hypervisor_config.json` file, and the sub-script is responsible for extracting the relevant section itself using `jq`.

*   **Pros:** Simple data-passing mechanism.
*   **Cons:**
    *   **Tighter Coupling:** Creates a strong dependency between the sub-script and the master configuration file's structure.
    *   **Violates Separation of Concerns:** The sub-script's responsibility should be to process its specific configuration, not to know the layout of a higher-level file.

### Option 4: Refactor Sub-script to Accept JSON via Standard Input (Recommended)

This solution involves modifying the sub-script to handle reading configuration data from `stdin` and updating the orchestrator to pipe the relevant JSON snippet to it.

*   **Pros:**
    *   **Optimal Decoupling:** The sub-script becomes a self-contained utility that processes a data stream without knowledge of its origin.
    *   **Follows Unix Philosophy:** Adheres to the principle of creating small, focused tools that work together using standard streams.
    *   **Enhanced Testability:** The sub-script can be easily tested in isolation by piping sample JSON data to it.
    *   **Clean and Maintainable:** The data flow is explicit and avoids the side effects of temporary files or environment variables.

## 5. Final Recommendation and Go-Forward Plan

**The recommended and target solution is Option 4: Complete the refactor to pass JSON data from the orchestrator to sub-scripts via standard input.**

This approach provides the most robust, maintainable, and architecturally sound solution. It establishes a clean contract: the orchestrator is responsible for slicing the master configuration, and the sub-modules are responsible for acting on those slices. This separation of concerns is critical for building a scalable and resilient system.

The `hypervisor_feature_setup_zfs.sh` script is already compliant. The remaining work is to update the `phoenix_orchestrator.sh` script to align with this strategy.

### Implementation Plan

The call in `phoenix_orchestrator.sh` should be modified to extract the relevant configuration and pipe it to the sub-script.

**Current Call (Incorrect):**
```bash
# In phoenix_orchestrator.sh
# ...
if ! "$script_path" --config "$config_file" --mode "$zfs_setup_mode"; then
    log_fatal "Hypervisor setup script '$script' failed."
fi
# ...
```

**Target Implementation (Correct):**
```bash
# In phoenix_orchestrator.sh
# ...
if [[ "$script" == "hypervisor_feature_setup_zfs.sh" ]]; then
    # Extract the .zfs object from the main config
    local zfs_config_part
    zfs_config_part=$(jq '.zfs' "$config_file")

    # Pipe the JSON data to the sub-script's standard input
    if ! echo "$zfs_config_part" | "$script_path" --config - --mode "$zfs_setup_mode"; then
        log_fatal "Hypervisor setup script '$script' failed."
    fi
else
    # Fallback for other scripts
    if ! "$script_path" "$config_file"; then
        log_fatal "Hypervisor setup script '$script' failed."
    fi
fi
# ...
```

This change will complete the implementation of the desired architectural pattern, leading to a more predictable and developer-friendly codebase.