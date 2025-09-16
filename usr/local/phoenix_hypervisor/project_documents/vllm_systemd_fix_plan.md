# vLLM Systemd Service Creation Fix Plan

## 1. Problem Analysis

The `phoenix_hypervisor_feature_install_vllm.sh` script fails during the creation of the systemd service file for vLLM. The error message `lxc-attach: 920: ../src/lxc/attach.c: lxc_attach_run_command: 1841 No such file or directory - Failed to exec "--"` indicates that the `--` argument is being misinterpreted by the `lxc-attach` command, which is called by `pct exec`.

Upon inspection of the `phoenix_hypervisor_common_utils.sh` script, the `pct_exec` function is defined as follows:

```bash
pct_exec() {
    local ctid="$1"
    shift # Remove ctid from the arguments list
    local cmd_args=("$@")

    log_info "Executing in CTID $ctid: ${cmd_args[*]}"
    if ! pct exec "$ctid" -- "${cmd_args[@]}"; then
        log_error "Command failed in CTID $ctid: '${cmd_args[*]}'"
        return 1
    fi
    return 0
}
```

The function already includes the `--` separator when calling `pct exec`. However, the calls to `pct_exec` in `phoenix_hypervisor_feature_install_vllm.sh` also include `--`, leading to a duplicated separator and causing the command to fail.

## 2. Remediation Plan

The solution is to remove the redundant `--` from all `pct_exec` calls within the `phoenix_hypervisor_feature_install_vllm.sh` script where `bash -c` is used for a test condition.

The following lines will be modified:

- **Line 88:** `if pct_exec "$CTID" -- bash -c "[ -f '$container_cert_path' ]"; then`
- **Line 138:** `if pct_exec "$CTID" -- bash -c "[ -f '${vllm_dir}/bin/vllm' ]"; then`
- **Line 173:** `if pct_exec "$CTID" -- bash -c "[ -d '${vllm_repo_dir}' ]"; then`
- **Line 245:** `if ! pct_exec "$CTID" -- bash -c "[ -f \"$service_file_path\" ]"; then`

These lines will be changed to:

- **Line 88:** `if pct_exec "$CTID" bash -c "[ -f '$container_cert_path' ]"; then`
- **Line 138:** `if pct_exec "$CTID" bash -c "[ -f '${vllm_dir}/bin/vllm' ]"; then`
- **Line 173:** `if pct_exec "$CTID" bash -c "[ -d '${vllm_repo_dir}' ]"; then`
- **Line 245:** `if ! pct_exec "$CTID" bash -c "[ -f \"$service_file_path\" ]"; then`

## 3. Implementation

I will switch to **Code Mode** to apply these changes using `apply_diff`.

## 4. Verification

After applying the fix, the `phoenix_orchestrator.sh` script should be re-run for the container to confirm that the vLLM feature installation completes successfully without the `Failed to exec "--"` error.