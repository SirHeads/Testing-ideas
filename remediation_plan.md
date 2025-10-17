# Storage Architecture Remediation Plan

## 1. Issue

The hypervisor setup process is plagued by a combination of architectural flaws, race conditions, and stale configurations. The core issues are:

1.  **Incorrect Storage Management:** The `hypervisor_feature_setup_zfs.sh` script was incorrectly treating all ZFS datasets as direct Proxmox storage, including those intended for shared access via NFS and Samba.
2.  **Race Conditions:** The setup scripts were not waiting for critical services like NFS to be fully operational before dependent services tried to use them.
3.  **Stale Configurations:** Previous failed setup attempts have left behind incorrect and non-functional storage definitions within Proxmox, causing "unreachable" errors on subsequent runs.

## 2. Remediation

A comprehensive refactor of the storage setup process will be implemented to address these issues.

### 2.1. Declarative Configuration (`phoenix_hypervisor_config.json`)

*   The `storage_class` property will be used to differentiate between `"direct"` and `"shared"` storage, ensuring that only appropriate datasets are managed by Proxmox.

### 2.2. Declarative ZFS Script (`hypervisor_feature_setup_zfs.sh`)

*   The `add_proxmox_storage` function will be rewritten to be fully declarative. It will:
    1.  Read the desired state of `"direct"` storage from the configuration file.
    2.  Get the current state of storage from Proxmox.
    3.  Remove any storage configurations that exist in Proxmox but are not in the desired state.
    4.  Add or update storage configurations to match the desired state.

### 2.3. Service Readiness (`hypervisor-manager.sh`)

*   A `wait_for_nfs_ready` function will be added to the `hypervisor-manager.sh` script to resolve the race condition, ensuring that the NFS service is fully operational before the ZFS script runs.

## 3. Expected Outcome

After applying these changes, the `phoenix setup` command will be robust, idempotent, and architecturally sound. It will correctly configure the storage, remove any stale configurations, and complete successfully without race conditions.
