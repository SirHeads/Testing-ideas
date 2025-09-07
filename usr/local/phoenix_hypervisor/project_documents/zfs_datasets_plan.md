# Revised ZFS Dataset Structure and Configuration Plan

This plan incorporates detailed requirements for ZFS dataset configuration, focusing on performance, data integrity, and NVMe optimization for the `quickOS` and `fastData` pools.

## 1. Proposed ZFS Dataset Structure

```mermaid
graph TD
    subgraph fastData Pool [fastData - 4TB NVMe]
        A[fastData/shared-test-data]
        B[fastData/shared-backups]
        C[fastData/shared-iso]
        D[fastData/shared-bulk-data]
    end

    subgraph quickOS Pool [quickOS - 2TB NVMe Mirror]
        E[quickOS/vm-disks]
        F[quickOS/lxc-disks]
        G[quickOS/shared-prod-data]
        H[quickOS/shared-prod-data-sync]
    end
```

## 2. ZFS Dataset Configuration Details

### On `quickOS` Pool (Mirrored 2TB NVMe)

| Dataset | Purpose & Content | Configuration | Mounting Strategy |
| :--- | :--- | :--- | :--- |
| **`quickOS/vm-disks`** | Block storage for VM root disks (OS, binaries). | `recordsize=128K`, `compression=lz4`, `sync=standard`, `quota=800G`. Sub-datasets per VM. | Proxmox block storage (ZFS backend). |
| **`quickOS/lxc-disks`** | Block storage for LXC root disks (OS, binaries). | `recordsize=16K`, `compression=lz4`, `sync=standard`, `quota=600G`. Sub-datasets per LXC. | Proxmox block storage (ZFS backend). |
| **`quickOS/shared-prod-data`** | Shared storage for LLM models, application data (non-database). | `recordsize=128K`, `compression=lz4`, `sync=standard`, `quota=400G`. | NFS (`noatime`, `async`) for VMs, bind-mount (`discard`, `noatime`) for LXCs. |
| **`quickOS/shared-prod-data-sync`** | Shared storage for databases requiring synchronous writes. | `recordsize=16K`, `compression=lz4`, `sync=always`, `quota=100G`. | NFS (`sync`, `noatime`) for VMs, bind-mount (`discard`, `noatime`) for LXCs. |

### On `fastData` Pool (Single 4TB NVMe)

| Dataset | Purpose & Content | Configuration | Mounting Strategy |
| :--- | :--- | :--- | :--- |
| **`fastData/shared-test-data`** | Test environment storage, cloned from production data. | `recordsize=128K` or `16K`, `compression=lz4`, `sync=standard`, `quota=500G`. | NFS (`noatime`, `async`) for VMs, bind-mount (`discard`, `noatime`) for LXCs. |
| **`fastData/shared-backups`** | Proxmox backups and snapshots of production data. | `recordsize=1M`, `compression=zstd`, `sync=standard`, `quota=2T`. | Proxmox backup storage. |
| **`fastData/shared-iso`** | Storage for ISO images. | `recordsize=1M`, `compression=lz4`, `sync=standard`, `quota=100G`. | Proxmox ISO storage. |
| **`fastData/shared-bulk-data`** | General-purpose storage for large files (media, logs). | `recordsize=1M`, `compression=lz4`, `sync=standard`, `quota=1.4T`. | NFS (`noatime`, `async`) for VMs, bind-mount (`discard`, `noatime`) for LXCs. |

## 3. Additional Requirements: NVMe Optimization

-   **TRIM**: `autotrim=on` will be set on both pools to maintain NVMe performance and lifespan.
-   **Write Amplification**:
    -   `lz4` and `zstd` compression will be used to reduce the amount of data written to the drives.
    -   Synchronous writes are isolated to the `quickOS/shared-prod-data-sync` dataset to minimize wear.
-   **Monitoring**: NVMe wear will be monitored using `smartctl`.
-   **Firmware**: It is recommended to ensure NVMe firmware is up-to-date.

## 4. Implementation Plan

1.  **Define Datasets in `phoenix_hypervisor_config.json`**: The next step is to translate this plan into the `zfs.datasets` array in the configuration file.
2.  **Execute ZFS Setup Script**: Run the `hypervisor_feature_setup_zfs.sh` script to create the pools and datasets.
3.  **Configure Proxmox Storage**: Add the datasets as storage resources in Proxmox.
4.  **Configure Mounts and Permissions**: Set up NFS exports and bind mounts for VMs and LXCs, and configure permissions as required.

This revised plan provides a solid foundation for a high-performance, reliable, and efficient storage architecture.
## 5. JSON Configuration for `phoenix_hypervisor_config.json`

The following JSON snippet should be used to update the `zfs` section of the `phoenix_hypervisor_config.json` file.

```json
"zfs": {
    "pools": [
        {
            "name": "quickOS",
            "raid_level": "mirror",
            "disks": [
                "__DISK_ID_1__",
                "__DISK_ID_2__"
            ]
        },
        {
            "name": "fastData",
            "raid_level": "single",
            "disks": [
                "__DISK_ID_3__"
            ]
        }
    ],
    "datasets": [
        {
            "name": "vm-disks",
            "pool": "quickOS",
            "properties": {
                "recordsize": "128K",
                "compression": "lz4",
                "sync": "standard",
                "quota": "800G"
            }
        },
        {
            "name": "lxc-disks",
            "pool": "quickOS",
            "properties": {
                "recordsize": "16K",
                "compression": "lz4",
                "sync": "standard",
                "quota": "600G"
            }
        },
        {
            "name": "shared-prod-data",
            "pool": "quickOS",
            "properties": {
                "recordsize": "128K",
                "compression": "lz4",
                "sync": "standard",
                "quota": "400G"
            }
        },
        {
            "name": "shared-prod-data-sync",
            "pool": "quickOS",
            "properties": {
                "recordsize": "16K",
                "compression": "lz4",
                "sync": "always",
                "quota": "100G"
            }
        },
        {
            "name": "shared-test-data",
            "pool": "fastData",
            "properties":. {
                "recordsize": "128K",
                "compression": "lz4",
                "sync": "standard",
                "quota": "500G"
            }
        },
        {
            "name": "shared-backups",
            "pool": "fastData",
            "properties": {
                "recordsize": "1M",
                "compression": "zstd",
                "sync": "standard",
                "quota": "2T"
            }
        },
        {
            "name": "shared-iso",
            "pool": "fastData",
            "properties": {
                "recordsize": "1M",
                "compression": "lz4",
                "sync": "standard",
                "quota": "100G"
            }
        },
        {
            "name": "shared-bulk-data",
            "pool": "fastData",
            "properties": {
                "recordsize": "1M",
                "compression": "lz4",
                "sync": "standard",
                "quota": "1.4T"
            }
        }
    ],
    "arc_max": "32212254720"
}
```

**Note**: The `__DISK_ID_...__` placeholders will need to be replaced with the actual disk identifiers during implementation.
## 7. Proposed Code Change for `phoenix_orchestrator.sh`

To ensure that the ZFS configuration is validated before any setup scripts are executed, the following change should be made to the `handle_hypervisor_setup_state` function in `phoenix_hypervisor/bin/phoenix_orchestrator.sh`.

```diff
--- a/phoenix_hypervisor/bin/phoenix_orchestrator.sh
+++ b/phoenix_hypervisor/bin/phoenix_orchestrator.sh
@@ -921,6 +921,11 @@
      fi
      log_info "Hypervisor configuration validated successfully."
  
+    # 2. Validate ZFS pool configuration
+    if [ "$(jq '.zfs.pools | length' "$VM_CONFIG_FILE")" -eq 0 ]; then
+        log_warn "No ZFS pools are defined in the configuration file. ZFS setup will be skipped."
+    fi
+
      # 2. Execute hypervisor feature scripts in sequence
      # Execute hypervisor feature scripts in a predefined sequence
      log_info "Executing hypervisor setup feature scripts..."

```