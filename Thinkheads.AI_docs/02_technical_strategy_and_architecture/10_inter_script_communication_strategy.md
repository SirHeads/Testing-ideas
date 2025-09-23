# Inter-Script Communication Strategy for Phoenix Hypervisor

**Author:** Roo, Architect
**Version:** 1.0
**Date:** 2025-09-23

## 1. Problem Statement

The `phoenix_orchestrator.sh` script, which serves as the central controller for the Phoenix Hypervisor framework, needs to pass structured configuration data to specialized sub-scripts. Specifically, it must provide the `.zfs` configuration object from the master `phoenix_hypervisor_config.json` file to the `hypervisor_feature_setup_zfs.sh` script.

A previous implementation attempted to pipe the JSON data directly to the sub-script's standard input. This failed because the sub-script is designed to accept a file path as an argument and validates the existence of that file, causing the process to fail when it receives a stream (`-`) instead of a path. The immediate tactical solution is using a temporary file, but this approach lacks robustness and introduces state management overhead, necessitating a more sound architectural solution.

## 2. Analysis of Requirements

The ideal solution must adhere to the following principles:

*   **Decoupling:** The orchestrator and sub-scripts should be loosely coupled. Sub-scripts should not have intimate knowledge of the master configuration file's structure.
*   **Clarity:** The flow of data from the orchestrator to the sub-script should be explicit and easy to follow.
*   **Robustness:** The mechanism must be reliable and handle potential errors gracefully.
*   **Security:** The method should not expose sensitive configuration data unnecessarily.
*   **Maintainability:** The solution should be easy for developers to understand, modify, and debug.

## 3. Evaluated Solutions

### Option 1: Temporary Files (Tactical Fix)

This approach involves the orchestrator extracting the relevant JSON section into a temporary file and passing the path of that file to the sub-script.

*   **Pros:**
    *   Simple and quick to implement.
    *   Requires no changes to the sub-script's argument parsing logic.
*   **Cons:**
    *   **State Management:** Requires a robust cleanup mechanism (e.g., using `trap`) to ensure the temporary file is deleted under all conditions, including script failure.
    *   **Filesystem Clutter:** Can leave orphaned files if not managed perfectly.
    *   **Lack of Elegance:** It's a workaround, not a clean architectural pattern.

### Option 2: Environment Variables

The orchestrator could export the JSON data as an environment variable before calling the sub-script.

*   **Pros:**
    *   Avoids filesystem operations.
*   **Cons:**
    *   **Clumsy for Structured Data:** Shell environments are not ideal for passing complex, multi-line JSON objects. The data would need to be passed as a single, unwieldy string.
    *   **Size Limitations:** Environment variables have size limits, which could be exceeded by complex configurations.
    *   **Security Risk:** Can expose configuration data to other processes in the environment.
    *   **Poor Readability:** Makes debugging difficult as the data is not easily visible.

### Option 3: Refactor Sub-script to Accept Full Config Path

The orchestrator could pass the path to the main `phoenix_hypervisor_config.json` file, and the sub-script would be responsible for extracting the `.zfs` section itself using `jq`.

*   **Pros:**
    *   Simple data-passing mechanism (a single file path).
*   **Cons:**
    *   **Tighter Coupling:** This creates a strong dependency between the sub-script and the master configuration file's structure. If the location of the `.zfs` object changes in the main file (e.g., moved under a new parent key), the sub-script will break.
    *   **Violates Separation of Concerns:** The sub-script's responsibility should be to process ZFS configuration, not to know the layout of a higher-level configuration file.

### Option 4: Refactor Sub-script to Accept JSON via Standard Input (Recommended)

This solution involves modifying the sub-script to correctly handle reading configuration data from `stdin` when instructed. This aligns with the original, elegant design pattern that was attempted.

*   **Pros:**
    *   **Optimal Decoupling:** The sub-script becomes a self-contained utility. It receives a stream of data and processes it, without any knowledge of its origin (file, pipe, etc.).
    *   **Follows Unix Philosophy:** Adheres to the principle of creating small, focused tools that work together using standard streams.
    *   **Enhanced Testability:** The sub-script can be easily tested in isolation by piping sample JSON data to it, without needing a full configuration file on disk.
    *   **Clean and Maintainable:** The data flow is explicit and avoids the side effects of temporary files or environment variables.

## 4. Final Recommendation and Justification

**The recommended solution is Option 4: Refactor the sub-script to correctly accept JSON data from standard input.**

This approach provides the most robust, maintainable, and architecturally sound solution. It establishes a clear and clean contract between the orchestrator and its sub-modules: the orchestrator is responsible for slicing the master configuration, and the sub-modules are responsible for acting on those slices. This separation of concerns is critical for building a scalable and resilient system.

By fixing the sub-script's argument parsing, we align the implementation with best practices for inter-process communication in a shell environment, leading to a more predictable and developer-friendly codebase.

### Implementation Example

The call in `phoenix_orchestrator.sh` remains elegant and correct:

```bash
# In phoenix_orchestrator.sh

# ...
local zfs_config_part
zfs_config_part=$(jq '.zfs' "$config_file")

# The pipe sends the JSON data to the sub-script's standard input
echo "$zfs_config_part" | "$script_path" --config - --mode safe
# ...
```

The change would be in `hypervisor_feature_setup_zfs.sh` to handle the `-` argument, which conventionally means "read from stdin". The script would read the piped JSON into a variable for processing.