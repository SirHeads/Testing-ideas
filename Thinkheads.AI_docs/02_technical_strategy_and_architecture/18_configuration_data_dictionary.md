---
title: Configuration Data Dictionary
summary: A comprehensive data dictionary for the JSON configuration files used in the Phoenix Hypervisor project.
document_type: Technical Reference
status: Draft
version: 1.0.0
author: Roo
owner: Technical VP
tags:
  - Configuration
  - Data Dictionary
  - JSON
review_cadence: Quarterly
last_reviewed: 2025-09-29
---

# Configuration Data Dictionary

This document provides a detailed explanation of the JSON configuration files that drive the Phoenix Hypervisor.

## 1. `phoenix_hypervisor_config.json`

This file contains global settings for the hypervisor, including network configuration, storage, and default settings for VMs and LXC containers.

### Top-Level Keys

*   `version`: The version of the configuration file.
*   `author`: The author of the configuration file.
*   `users`: Defines the administrative user for the hypervisor.
*   `core_paths`: Defines core paths for the Phoenix Hypervisor framework.
*   `timezone`: The timezone for the hypervisor.
*   `network`: Global network settings for the hypervisor.
*   `docker`: Default Docker settings.
*   `nfs`: NFS server settings.
*   `samba`: Samba server settings.
*   `zfs`: ZFS pool and dataset configurations.
*   `proxmox_storage_ids`: Mappings for Proxmox storage IDs.
*   `mount_point_base`: The base mount point for Proxmox storage.
*   `proxmox_defaults`: Default settings for Proxmox.
*   `tests`: Defines test suites for the hypervisor.
*   `nvidia_driver`: NVIDIA driver installation settings.
*   `behavior`: Defines the behavior of the orchestrator.
*   `shared_volumes`: Defines shared volumes to be mounted into containers.

## 2. `phoenix_lxc_configs.json`

This file contains the specific configurations for each LXC container.

### Top-Level Keys

*   `$schema`: The path to the JSON schema for this file.
*   `nvidia_driver_version`: The version of the NVIDIA driver to be used.
*   `nvidia_repo_url`: The URL for the NVIDIA repository.
*   `nvidia_runfile_url`: The URL for the NVIDIA runfile.
*   `lxc_configs`: An object containing the configurations for each LXC container, keyed by the container ID.

### LXC Container Configuration (`lxc_configs.<CTID>`)

*   `name`: The hostname of the container.
*   `start_at_boot`: Whether the container should start at boot.
*   `boot_order`: The boot order of the container.
*   `boot_delay`: The boot delay for the container.
*   `memory_mb`: The amount of memory to allocate to the container in MB.
*   `cores`: The number of CPU cores to allocate to the container.
*   `template`: The path to the template to use for creating the container.
*   `storage_pool`: The storage pool to use for the container's root filesystem.
*   `storage_size_gb`: The size of the container's root filesystem in GB.
*   `network_config`: The network configuration for the container.
*   `mac_address`: The MAC address for the container's network interface.
*   `gpu_assignment`: The GPU(s) to assign to the container.
*   `portainer_role`: The Portainer role for the container.
*   `unprivileged`: Whether the container should be unprivileged.
*   `clone_from_ctid`: The ID of the container to clone from.
*   `features`: An array of feature scripts to apply to the container.
*   `lxc_options`: An array of LXC options to apply to the container.
*   `template_snapshot_name`: The name of the snapshot to create for template containers.
*   `apparmor_profile`: The AppArmor profile to apply to the container.
*   `apparmor_manages_nesting`: Whether AppArmor should manage nesting for the container.
*   `application_script`: The application script to run in the container.
*   `ports`: An array of ports to forward to the container.
*   `health_check`: The health check command to run in the container.
*   `firewall`: The firewall rules for the container.
*   `dependencies`: An array of container IDs that this container depends on.
*   `volumes`: An array of dedicated volumes to mount into the container.
*   `zfs_volumes`: An array of ZFS volumes to mount into the container.
*   `pct_options`: An array of `pct` options to apply to the container.
*   `tests`: Defines test suites for the container.