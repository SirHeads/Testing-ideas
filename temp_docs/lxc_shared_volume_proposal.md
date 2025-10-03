# Proposal: Align LXC Volume Mounting with VM Strategy

## 1. Problem Statement & Revised Strategy

My initial analysis revealed that the `lxc-manager.sh` script does not handle the mounting of shared host directories, leading to a configuration gap for new containers like `101`. My first proposal suggested a global `shared_volumes` key.

Based on user feedback, this approach is inconsistent with the `vm-manager.sh` script, which defines volumes within each VM's configuration. To ensure architectural alignment, this proposal has been revised to adopt the VM pattern for LXC containers.

The new strategy is to define host-path mounts directly within each container's configuration block in `phoenix_lxc_configs.json` and enhance `lxc-manager.sh` to apply them.

## 2. Proposed Solution

### 2.1. Configuration Schema Change

I propose adding a new optional array, `mount_points`, to the LXC container schema in `phoenix_lxc_configs.json`. Each object in this array will define a host-to-container mount.

**Example for Container `101`:**
```json
"101": {
    "name": "Nginx-Phoenix",
    ...
    "mount_points": [
        {
            "host_path": "/usr/local/phoenix_hypervisor/etc/nginx/sites-available",
            "container_path": "/etc/nginx/sites-available"
        },
        {
            "host_path": "/mnt/pve/quickOS/shared-prod-data/ssl",
            "container_path": "/etc/nginx/ssl"
        },
        {
            "host_path": "/mnt/pve/quickOS/shared-prod-data/logs/nginx",
            "container_path": "/logs/nginx"
        }
    ],
    ...
}
```

### 2.2. New Function in `lxc-manager.sh`: `apply_mount_points`

A new function, `apply_mount_points`, will be added to `lxc-manager.sh`. This function will read the `mount_points` array from the container's configuration and apply the mounts idempotently.

```bash
# =====================================================================================
# Function: apply_mount_points
# Description: Mounts shared host directories into the container as defined in the
#              container's specific configuration.
# =====================================================================================
apply_mount_points() {
    local CTID="$1"
    log_info "Applying host path mount points for CTID: $CTID..."

    local mounts
    mounts=$(jq_get_value "$CTID" ".mount_points // [] | .[]" || echo "")
    if [ -z "$mounts" ]; then
        log_info "No host path mount points to apply for CTID $CTID."
        return 0
    fi

    local volume_index=0
    # Find the next available mount point index
    while pct config "$CTID" | grep -q "mp${volume_index}:"; do
        volume_index=$((volume_index + 1))
    done

    for mount_config in $(echo "$mounts" | jq -c '.'); do
        local host_path=$(echo "$mount_config" | jq -r '.host_path')
        local container_path=$(echo "$mount_config" | jq -r '.container_path')
        local mount_id="mp${volume_index}"
        local mount_string="${host_path},mp=${container_path}"

        # Idempotency Check
        if ! pct config "$CTID" | grep -q "mp.*: ${mount_string}"; then
            log_info "Applying mount: ${host_path} -> ${container_path}"
            run_pct_command set "$CTID" --"${mount_id}" "$mount_string" || log_fatal "Failed to apply mount."
            volume_index=$((volume_index + 1))
        else
            log_info "Mount point ${host_path} -> ${container_path} already configured."
        fi
    done
}
```

### 2.3. Integration into the Orchestration Workflow

The new `apply_mount_points` function will be called within the `create` case of the `main_lxc_orchestrator` function in `lxc-manager.sh`.

```diff
--- a/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
+++ b/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
@@ -1075,6 +1075,7 @@
                 
                 apply_configurations "$ctid"
                 apply_zfs_volumes "$ctid"
+                apply_mount_points "$ctid"
                 apply_dedicated_volumes "$ctid"
                 ensure_container_disk_size "$ctid"
                 
```

## 3. Architectural Diagram

This revised solution creates a consistent configuration pattern for both LXC containers and VMs.

```mermaid
graph TD
    subgraph "Guest Configuration"
        A[phoenix_lxc_configs.json <br> .lxc_configs.[CTID].mount_points]
        B[phoenix_vm_configs.json <br> .vms.[VMID].volumes]
    end

    subgraph "Orchestration"
        C{lxc-manager.sh}
        D{vm-manager.sh}
    end

    subgraph "Guest Instance"
        E[LXC Container]
        F[VM Guest]
    end

    A --> C;
    B --> D;
    C -- "pct set ..." --> E;
    D -- "qm set ..." --> F;
```

## 4. Benefits

*   **Architectural Consistency**: The configuration of LXC mount points now mirrors the established pattern for VM volumes.
*   **Self-Contained Definitions**: Each guest's configuration is self-contained, improving readability and maintainability.
*   **Declarative & Idempotent**: The solution adheres to the core principles of the Phoenix Hypervisor project.

This aligned approach provides a clean and robust path forward for making container `101` a true, declaratively-configured replacement for `953`.