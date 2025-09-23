# Plan to Resolve `pct_exec` Inconsistency

This plan outlines the steps to fix the immediate bug caused by the incorrect usage of the `pct_exec` function and to improve the codebase to prevent similar issues in the future.

## 1. Fix the Incorrect `pct_exec` Call

The immediate issue is in `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_nvidia.sh`. The call to `pct_exec` on line 154 includes an unnecessary `--`.

**File to be modified:** `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_nvidia.sh`

**Change:**
```diff
-    if ! pct_exec "$CTID" -- [ -c /dev/nvidia0 ]; then
+    if ! pct_exec "$CTID" [ -c /dev/nvidia0 ]; then
```

## 2. Improve `pct_exec` Documentation

To prevent this from happening again, the documentation for the `pct_exec` function in `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh` will be updated to explicitly warn against adding `--`.

**File to be modified:** `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh`

**Change:**
I will add a note to the function's description.

```bash
# =====================================================================================
# Function: pct_exec
# Description: Executes a command inside an LXC container using 'pct exec'.
#              Handles errors and ensures commands are run with appropriate privileges.
#              NOTE: This function automatically handles the '--' separator. Do not include it in your command.
# Arguments:
#   $1 (ctid) - The container ID.
#   $@ - The command and its arguments to execute inside the container.
# =====================================================================================
```

## 3. Implementation

After your approval of this plan, I will switch to **Code Mode** to apply these changes.

## 4. Final Review

Once the changes are implemented, I will provide a final summary for you to review and confirm that all work is done and done correctly.