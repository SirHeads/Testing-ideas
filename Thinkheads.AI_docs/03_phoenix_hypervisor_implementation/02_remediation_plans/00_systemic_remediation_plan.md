---
title: Systemic Remediation Plan
summary: This plan outlines a comprehensive, system-wide solution to address recent scripting failures, including enhancements to pct_exec and bug fixes for check_nvidia.sh.
document_type: Remediation Plan
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Developer
tags:
  - Remediation
  - Shell Scripts
  - Bug Fix
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Plan for Systemic Remediation of Scripting Issues

This plan outlines a comprehensive, system-wide solution to address the recent scripting failures. The goal is to not only fix the immediate bugs but also to improve the overall resilience and quality of the scripting environment.

## 1. Enhance `pct_exec` for Robustness

The `pct_exec` function in `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh` will be enhanced to intelligently handle the `--` separator. This will make the function more forgiving and prevent a class of errors from recurring.

**File to be modified:** `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh`

**Change:**
The function will be updated to check for and remove a leading `--` from the command arguments.

```bash
pct_exec() {
    local ctid="$1"
    shift
    if [[ "$1" == "--" ]]; then
        shift
    fi
    local cmd_args=("$@")
    # ... rest of the function
}
```

## 2. Fix `check_nvidia.sh` Scoping Bug

The script `usr/local/phoenix_hypervisor/bin/health_checks/check_nvidia.sh` will be refactored to correctly scope its variables by wrapping the main logic in a `main` function.

**File to be modified:** `usr/local/phoenix_hypervisor/bin/health_checks/check_nvidia.sh`

**Change:**
The script will be restructured as follows:

```bash
#!/bin/bash
# ... header ...

# --- Source common utilities ---
# ...

main() {
    local CTID="$1"
    if [ -z "$CTID" ]; then
        log_fatal "Usage: $0 <CTID>"
    fi

    log_info "Verifying NVIDIA installation in CTID: $CTID"
    local target_version
    target_version=$(jq_get_value "$CTID" ".nvidia_driver_version")

    local installed_version
    # ... rest of the logic ...
}

main "$@"
```

## 3. Create a Validation Test Script

A new test script, `usr/local/phoenix_hypervisor/bin/tests/validate_systemic_fixes.sh`, will be created to verify both fixes. This script will:

*   Call `pct_exec` with and without the `--` separator to confirm both work.
*   Execute the corrected `check_nvidia.sh` to ensure it runs without errors.

## 4. Update Documentation

The documentation for `pct_exec` will be updated to reflect its new, more robust behavior.

## 5. Implementation

After your approval of this plan, I will switch to **Code Mode** to apply these changes.