# Phoenix Setup Command Workflow Summary

This document outlines the sequence of operations performed by the `phoenix setup` command.

## 1. Initial Dispatch

- The main `phoenix-cli` script receives the `setup` verb.
- It recognizes this as a special command that operates on the hypervisor itself.
- The command and all its arguments (e.g., `--wipe-disks`) are forwarded directly to the `hypervisor-manager.sh` script for execution.

## 2. Hypervisor Manager Orchestration

The `hypervisor-manager.sh` script orchestrates the entire setup process by executing a series of modular scripts in a specific, hardcoded order. This ensures a consistent and reliable setup.

The sequence of execution is as follows:

```mermaid
graph TD
    A[Start: phoenix setup] --> B{hypervisor-manager.sh};
    B --> C[hypervisor_initial_setup.sh];
    C --> D[hypervisor_feature_setup_zfs.sh];
    D --> E[hypervisor_feature_setup_firewall.sh];
    E --> F[hypervisor_feature_setup_nfs.sh];
    F --> G[Wait for NFS Ready];
    G --> H[hypervisor_feature_configure_vfio.sh];
    H --> I[hypervisor_feature_install_nvidia.sh];
    I --> J[hypervisor_feature_initialize_nvidia_gpus.sh];
    J --> K[hypervisor_feature_setup_dns_server.sh];
    K --> L[hypervisor_feature_create_heads_user.sh];
    L --> M[hypervisor_feature_setup_samba.sh];
    M --> N[hypervisor_feature_create_admin_user.sh];
    N --> O[hypervisor_feature_provision_shared_resources.sh];
    O --> P[hypervisor_feature_setup_apparmor.sh];
    P --> Q[hypervisor_feature_fix_apparmor_tunables.sh];
    Q --> R{create_global_symlink};
    R --> S[End: Setup Complete];
```

## 3. Key Steps and Logic

- **ZFS Setup**: The `hypervisor_feature_setup_zfs.sh` script is called with a `--mode` argument. This is `safe` by default, but changes to `force-destructive` if the `--wipe-disks` flag is used with the initial `phoenix setup` command.
- **NFS Synchronization**: After the NFS server is configured, the manager script pauses and waits for the NFS shares to become available before proceeding. This prevents race conditions with subsequent scripts that might depend on those shares.
- **Finalization**: Once all setup scripts have completed successfully, the `create_global_symlink` function is called. This creates a symbolic link at `/usr/local/bin/phoenix`, making the command globally accessible in the system's PATH.

This structured and sequential process ensures that all dependencies are met at each stage of the hypervisor configuration.