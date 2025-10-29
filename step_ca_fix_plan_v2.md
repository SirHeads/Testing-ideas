# Step-CA Synchronization Fix Plan v2

This document outlines the revised plan to resolve the Step-CA race condition by refactoring the VM certificate management process to align with the proven, robust pattern used by the LXC containers.

## 1. Core Principle

The fundamental flaw in the current VM process is the "push" model, where the hypervisor injects files into the VM. We will replace this with the "pull" model used by the LXCs, where the VM mounts the shared CA state and manages its own certificate lifecycle.

## 2. The Plan

### Step 1: Unify the Shared Volume for VMs

The VM must have access to the same single source of truth as the LXCs. We will achieve this by modifying its volume configuration.

*   **File to Modify:** `usr/local/phoenix_hypervisor/etc/phoenix_vm_configs.json`
*   **Change:** For VM 1001, we will add a second volume mount. This new mount will be specifically for the Step-CA shared directory. The existing persistent storage volume will remain for other data.

**Target Addition to VM 1001 `volumes` array:**
```json
{
    "type": "nfs",
    "name": "step-ca-ssl",
    "path": "/mnt/pve/quickOS/lxc-persistent-data/103/ssl",
    "mount_point": "/etc/step-ca/ssl",
    "server": "10.0.0.13"
}
```

### Step 2: Remove Fragile File Injection Logic

The `inject_files_into_vm` function in the VM manager is the source of the race condition and is no longer needed. We will remove the call to this function.

*   **File to Modify:** `usr/local/phoenix_hypervisor/bin/managers/vm-manager.sh`
*   **Change:** In the `orchestrate_vm` function, locate and delete the block that calls `inject_files_into_vm`.

**Block to Delete (around line 293):**
```bash
        log_info "Step 9: Injecting necessary files into VM $VMID..."
        inject_files_into_vm "$VMID"
        log_info "Step 9: Completed."
```

### Step 3: Implement Robust Synchronization Inside the VM

We will replicate the intelligent wait mechanism from the Traefik container's script inside the VM's Docker feature script. The VM will now be responsible for waiting until the CA is ready before proceeding.

*   **File to Modify:** `usr/local/phoenix_hypervisor/bin/vm_features/feature_install_docker.sh`
*   **Changes:**
    1.  **Add a `wait_for_ca` function** at the beginning of the script. This function will poll for the existence of the `/etc/step-ca/ssl/ca.ready` file.
    2.  **Call this function** immediately after sourcing the common utilities.
    3.  **Modify the script to use the new mount point.** The paths for the fingerprint and provisioner password files will be changed from `/tmp/` to `/etc/step-ca/ssl/`.

**New `wait_for_ca` function to add:**
```bash
wait_for_ca() {
    local CA_READY_FILE="/etc/step-ca/ssl/ca.ready"
    log_info "Waiting for Step CA to become ready..."
    local timeout=300 # 5 minutes
    local start_time=$(date +%s)

    while (( ($(date +%s) - start_time) < timeout )); do
        if [ -f "${CA_READY_FILE}" ]; then
            log_success "Step CA is ready."
            return 0
        fi
        log_info "CA not ready yet. Waiting 5 seconds..."
        sleep 5
    done
    log_fatal "Timeout reached while waiting for Step CA."
}
```

**Modifications to the main body of the script:**
```bash
# ... after sourcing common_utils.sh
wait_for_ca

# ... later in the script, update file paths
INTERNAL_DNS_SERVER="10.0.0.1"
CA_URL="https://ca.internal.thinkheads.ai:9000"
PROVISIONER_PASSWORD_FILE="/etc/step-ca/ssl/provisioner_password.txt"
ROOT_CA_FINGERPRINT_FILE="/etc/step-ca/ssl/root_ca.fingerprint"
# ... rest of the script
```

## 4. Implementation Steps

1.  Switch to `code` mode.
2.  Apply the volume addition to `usr/local/phoenix_hypervisor/etc/phoenix_vm_configs.json`.
3.  Apply the function call removal to `usr/local/phoenix_hypervisor/bin/managers/vm-manager.sh`.
4.  Apply the new function and path changes to `usr/local/phoenix_hypervisor/bin/vm_features/feature_install_docker.sh`.
5.  Request the user to re-run the full environment recreation command to validate the fix.