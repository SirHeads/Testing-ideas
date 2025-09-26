# Unified AppArmor Strategy for Nested LXC Containers

This document outlines the new, unified AppArmor strategy for securing nested LXC containers that require GPU, Docker, and shared storage access. This approach resolves the conflict between Proxmox's default nesting profile and our custom security requirements.

## 1. The Core Problem

The error `explicitly configured lxc.apparmor.profile overrides the following settings: features:nesting` occurs because enabling `nesting` in an LXC container requires a specific set of AppArmor rules that are provided by Proxmox's default nesting profile. When we apply a custom profile, we override these essential rules, causing the container to fail to start.

## 2. The Solution: A Unified Profile

The solution is to create a new, unified AppArmor profile that merges the rules from Proxmox's default nesting profile with our custom rules. This ensures that all necessary permissions are in place for both nesting and our specific use case.

### New AppArmor Profile: `lxc-nesting-gpu-docker-storage`

This new profile, located at `/usr/local/phoenix_hypervisor/etc/apparmor/lxc-nesting-gpu-docker-storage`, will contain the following rules:

```
# Do not load this file. Rather, load /etc/apparmor.d/lxc-containers, which
# sources this file.

profile lxc-nesting-gpu-docker-storage flags=(attach_disconnected,mediate_deleted) {
  # Include the base container abstractions
  #include <abstractions/lxc/container-base>
  #include <abstractions/lxc/start-container>

  # Rules from Proxmox's default nesting profile
  deny /dev/.lxc/proc/** rw,
  deny /dev/.lxc/sys/** rw,
  mount fstype=proc -> /var/cache/lxc/**,
  mount fstype=sysfs -> /var/cache/lxc/**,
  mount options=(rw,bind),
  mount fstype=cgroup -> /sys/fs/cgroup/**,
  mount fstype=cgroup2 -> /sys/fs/cgroup/**,

  # Custom rules for GPU, Docker, and storage
  mount fstype=rpc_pipefs -> **,
  mount fstype=debugfs -> **,
  mount options=(rw,nosuid,nodev,noexec,relatime) -> /sys/kernel/debug/,

  # Allow mounts for nesting
  mount fstype=overlay,
  mount fstype=tmpfs,
  mount fstype=autofs,
  mount fstype=bpf,
  mount fstype=btrfs,
  mount fstype=devpts,
  mount fstype=efivarfs,
  mount fstype=fuse,
  mount fstype=fusectl,
  mount fstype=hugetlbfs,
  mount fstype=mqueue,
  mount fstype=nfs,
  mount fstype=nfs4,
  mount fstype=pstore,
  mount fstype=ramfs,
  mount fstype=securityfs,
  mount fstype=sysfs,
  mount fstype=tracefs,
  mount options=(ro,bind),
  mount options=(rbind),
  mount options=(rw,remount),
  mount options=(ro,remount),
  mount options=(rw,nosuid,nodev,noexec,relatime,bind),
  mount options=(rw,nosuid,nodev,noexec,relatime,remount),

  # Allow NVIDIA GPU device files
  /dev/nvidia* rwm,
  /dev/nvidia-uvm rwm,
  /dev/nvidia-uvm-tools rwm,
  /dev/nvidia-caps/* rwm,

  # Allow Docker
  /var/lib/docker/ r,
  /var/lib/docker/** rwm,
  /run/docker.sock rw,

  # Allow shared storage
  /mnt/shared/** rwm,

  # Deny writes to /proc/sys/fs/binfmt_misc/register
  deny audit mount fstype=binfmt_misc,

  # Audit write attempts to /etc/ for monitoring
  audit /etc/** w,
}
```

## 3. Implementation Plan

The implementation of this new strategy will be carried out by the `code` mode and will involve the following steps:

1.  **Create the New Profile:** The `lxc-nesting-gpu-docker-storage` file will be created with the content specified above.
2.  **Update LXC Configurations:** The `phoenix_lxc_configs.json` file will be updated to apply the new profile to all containers that have `nesting: 1` enabled.
3.  **Remediate `jq` Error:** The `phoenix_orchestrator.sh` script will be modified to handle cases where the `features` array is empty or null, preventing the `jq` error.

This new strategy will provide a robust and maintainable solution for securing our nested LXC containers.

## 4. LXC Configuration Changes

The following changes must be made to `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json` to apply the new AppArmor profile to the relevant containers.

### CTID 953: Nginx-VscodeRag

Update the `apparmor_profile` from `"unconfined"` to `"lxc-nesting-gpu-docker-storage"`.

```json
"953": {
    "name": "Nginx-VscodeRag",
    ...
    "apparmor_profile": "lxc-nesting-gpu-docker-storage",
    ...
},
```

## 5. Orchestrator Script (`jq`) Remediation

The `phoenix_orchestrator.sh` script currently fails when a container's `features` array is empty or null. To fix this, the `jq` queries in the script must be modified to handle these cases gracefully.

The following `jq` query should be updated in `phoenix_orchestrator.sh`:

**Current (failing) query:**
```bash
jq -r ".lxc_configs.\"$CTID\".features[]" "$LXC_CONFIG_FILE"
```

**Proposed (remediated) query:**
```bash
jq -r "(.lxc_configs.\"$CTID\".features // [])[]" "$LXC_CONFIG_FILE"
```

This change uses the `// []` operator to provide a default empty array if the `features` key is null or missing, preventing the `jq` command from failing. This same remediation should be applied to any other `jq` queries in the script that iterate over arrays that may be empty or null.

### CTID 954: n8n-phoenix

Update the `apparmor_profile` from `"unconfined"` to `"lxc-nesting-gpu-docker-storage"`.

```json
"954": {
    "name": "n8n-phoenix",
    ...
    "apparmor_profile": "lxc-nesting-gpu-docker-storage",
    ...
},
```