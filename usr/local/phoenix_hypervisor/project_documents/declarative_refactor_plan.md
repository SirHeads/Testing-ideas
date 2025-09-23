---
title: Declarative Refactor Plan
summary: This plan outlines a holistic refactoring of the scripting environment to align with the core architectural principles of declarative state and idempotency.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Refactoring
- Declarative State
- Idempotency
- Shell Scripts
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Plan for Declarative Refactor of Scripting

This plan outlines a holistic refactoring of the scripting environment to align with the core architectural principles of declarative state and idempotency. This approach will resolve the root cause of the recent failures and improve the overall resilience and maintainability of the system.

## 1. Embrace Declarative Logging

The `pct_exec` function in `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh` will be refactored to capture all output from the commands it executes. This aligns with the "Inspect" phase of the declarative model.

**File to be modified:** `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh`

**Change:**
The function will be updated to capture and return both stdout and stderr.

```bash
pct_exec() {
    local ctid="$1"
    shift
    # ... robust handling of '--' ...
    local cmd_args=("$@")
    
    local output
    output=$(pct exec "$ctid" -- "${cmd_args[@]}" 2>&1)
    echo "$output"
    return 0
}
```

## 2. Refactor `check_nvidia.sh` for Idempotency

The `check_nvidia.sh` script will be refactored to be fully idempotent and declarative. It will inspect the system for the correct driver version and report its findings.

**File to be modified:** `usr/local/phoenix_hypervisor/bin/health_checks/check_nvidia.sh`

**Change:**
The script will be restructured to focus on inspection and reporting.

```bash
main() {
    local CTID="$1"
    # ... argument parsing ...

    local output
    output=$(pct_exec "$CTID" nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits)
    
    local installed_version
    installed_version=$(echo "$output" | tail -n 1) # Extract the version from the output

    local target_version
    target_version=$(jq_get_value "$CTID" ".nvidia_driver_version")

    if [[ "$installed_version" == "$target_version" ]]; then
        log_info "NVIDIA driver version matches the target. Verification successful."
        return 0
    else
        log_fatal "NVIDIA driver version mismatch! Expected '$target_version', but found '$installed_version'."
    fi
}

main "$@"
```

## 3. Comprehensive Test Suite

A new, comprehensive test suite will be created to validate the refactored scripts and the declarative principles they embody.

## 4. Implementation

After your approval of this plan, I will switch to **Code Mode** to apply these changes.