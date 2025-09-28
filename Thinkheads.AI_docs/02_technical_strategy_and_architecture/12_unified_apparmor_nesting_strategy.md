# Unified AppArmor and Nesting Strategy for Phoenix Hypervisor

## 1. Introduction

This document outlines a unified strategy for managing AppArmor profiles and LXC nesting within the Phoenix Hypervisor environment. The goal is to establish a consistent, scalable, and maintainable approach that enhances security and simplifies container management.

## 2. Core Principles

*   **Consistency:** All containers with similar requirements should use the same AppArmor profile and nesting configuration.
*   **Idempotency:** The orchestration scripts should be able to apply the correct configuration repeatedly without causing errors.
*   **Scalability:** The strategy should be able to accommodate a growing number of containers and a variety of use cases.
*   **Single Source of Truth:** The `phoenix_lxc_configs.json` file should be the single source of truth for all container configurations.

## 3. The `lxc-docker-nested` AppArmor Profile

To address the challenges of running Docker in a nested environment, we will introduce a new AppArmor profile named `lxc-docker-nested`. This profile is designed to be a secure baseline for nested Docker containers.

### 3.1. Profile Content

```
#include <tunables/global>

profile lxc_docker_nested flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/lxc/container-base>
  #include <abstractions/lxc/start-container>

  # Core capabilities for container operation
  capability sys_admin,
  capability sys_chroot,
  capability mknod,
  capability sys_nice,
  capability sys_resource,
  capability net_bind_service,
  capability net_admin,
  capability mac_admin,

  # Network access
  network inet stream,
  network inet6 stream,
  network inet dgram,
  network inet6 dgram,
  network bridge,

  # DNS resolution
  /etc/resolv.conf r,
  /etc/hosts r,

  # Shared storage mounts
  /mnt/shared/** rwm,
  /zfs/storage/** rwm,

  # Deny access to sensitive host devices
  audit deny /dev/.lxc/proc/** rw,
  audit deny /dev/.lxc/sys/** rw,

  # Standard system filesystem mounts
  mount fstype=proc -> /proc/,
  mount fstype=sysfs -> /sys/,
  mount fstype=cgroup -> /sys/fs/cgroup/**,
  mount fstype=cgroup2 -> /sys/fs/cgroup/**,
  mount fstype=tmpfs -> /run/**,
  mount fstype=devpts -> /dev/pts/**,
  mount fstype=mqueue -> /dev/mqueue/**,

  # Allow necessary mounts for nesting and storage
  mount fstype=bpf -> /sys/fs/bpf/**,
  mount fstype=securityfs -> /sys/kernel/security/**,
  mount fstype=tracefs -> /sys/kernel/tracing/**,
  mount fstype=zfs -> /zfs/storage/**,

  # Allow bind mounts for shared storage
  mount options=(rw,bind) -> /mnt/**,
  mount options=(rw,remount) -> /mnt/**,
  mount options=(rw,nosuid,nodev,noexec,relatime,bind) -> /mnt/**,

  # Deny binfmt_misc by default for security
  # To enable multi-architecture container support, comment out the following line
  # and uncomment the line after it.
  audit deny mount fstype=binfmt_misc,
  # mount fstype=binfmt_misc -> /proc/sys/fs/binfmt_misc/,

  # Read-only access to home directories
  /home/*/ r,

  # Docker-specific permissions
  /var/run/docker.sock rw,
  /var/lib/docker/** rwm,
}
```

## 4. Standardized Configuration in `phoenix_lxc_configs.json`

All containers that require Docker will have the following configuration in the `phoenix_lxc_configs.json` file:

```json
"pct_options": [
    "nesting=1",
    "keyctl=1"
],
"apparmor_profile": "lxc-docker-nested"
```

**Note on ZFS:** The `mount fstype=zfs` rule in the AppArmor profile is dependent on the orchestrator correctly generating the `lxc.mount.entry` from the `zfs_volumes` definition in the JSON configuration.

## 5. Orchestration Logic

The `phoenix_orchestrator.sh` script will be updated to read the `apparmor_profile` and `pct_options` from the JSON configuration and apply them to each container. This ensures that the correct security policies and nesting features are enforced consistently.

## 6. Workflow Diagram

```mermaid
graph TD
    A[Start] --> B{Read phoenix_lxc_configs.json};
    B --> C{For each container};
    C --> D{Has apparmor_profile?};
    D -->|Yes| E[Apply AppArmor profile];
    D -->|No| F[Apply default profile];
    E --> G{Has pct_options?};
    F --> G;
    G -->|Yes| H[Apply pct_options];
    G -->|No| I[Continue];
    H --> J[Create/Start container];
    I --> J;
    J --> C;
    C --> K[End];