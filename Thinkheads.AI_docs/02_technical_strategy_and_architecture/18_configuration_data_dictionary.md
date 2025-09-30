---
title: Configuration Data Dictionary
summary: A comprehensive data dictionary for the JSON configuration files used in the Phoenix Hypervisor project.
document_type: Technical Reference
status: Active
version: 1.1.0
author: Roo
owner: Technical VP
tags:
  - Configuration
  - Data Dictionary
  - JSON
  - Phoenix Hypervisor
review_cadence: Quarterly
last_reviewed: 2025-09-30
---

# Configuration Data Dictionary

This document provides a detailed explanation of the JSON configuration files that drive the Phoenix Hypervisor. A clear understanding of these files is essential for operating, maintaining, and extending the platform.

## 1. `phoenix_hypervisor_config.json`

This file contains global settings for the hypervisor, including network configuration, storage, default settings for VMs and LXC containers, and orchestration behavior.

### Top-Level Keys

*   `version`: The version of the configuration file schema.
*   `author`: The author of the configuration file.
*   `users`: Defines the administrative user for the hypervisor, including username, password hash, and SSH key.
*   `core_paths`: Defines critical file paths for the Phoenix Hypervisor framework, such as the location of other configuration files and security tokens.
*   `timezone`: The system timezone for the hypervisor (e.g., "America/New_York").
*   `network`: Global network settings, including default gateways, DNS servers, and NFS server IP.
*   `docker`: Default Docker settings, including image names for Portainer.
*   `nfs`: NFS server settings, defining exported paths and client access rules.
*   `samba`: Samba server settings, defining shares, paths, and user access.
*   `zfs`: ZFS pool and dataset configurations, including RAID levels, disk assignments, and dataset properties.
*   `proxmox_storage_ids`: Mappings for Proxmox storage IDs to ZFS datasets.
*   `mount_point_base`: The base mount point for Proxmox storage (e.g., "/mnt/pve").
*   `proxmox_defaults`: Default settings for Proxmox, including default LXC configurations.
*   `tests`: Defines test suites for validating the hypervisor's health and functionality.
*   `nvidia_driver`: NVIDIA driver installation settings, including version and runfile URL.
*   `behavior`: Defines the behavior of the orchestrator, such as debug mode and rollback on failure.
*   `shared_volumes`: Defines shared volumes to be mounted into containers, mapping host paths to container paths.

## 2. `phoenix_lxc_configs.json`

This file contains the specific configurations for each LXC container, keyed by their Container ID (CTID).

### Top-Level Keys

*   `$schema`: The path to the JSON schema for this file, used for validation.
*   `nvidia_driver_version`: The version of the NVIDIA driver to be used in containers with GPU passthrough.
*   `nvidia_repo_url`: The URL for the NVIDIA repository.
*   `nvidia_runfile_url`: The URL for the NVIDIA runfile.
*   `lxc_configs`: An object containing the configurations for each LXC container, keyed by the container ID.

### LXC Container Configuration (`lxc_configs.<CTID>`)

*   `name`: The hostname of the container.
*   `start_at_boot`: (boolean) Whether the container should start automatically at boot.
*   `boot_order`: The boot order priority of the container.
*   `boot_delay`: The delay in seconds before starting the container.
*   `memory_mb`: The amount of memory to allocate to the container in MB.
*   `cores`: The number of CPU cores to allocate to the container.
*   `template`: The path to the template to use for creating the container.
*   `storage_pool`: The storage pool to use for the container's root filesystem.
*   `storage_size_gb`: The size of the container's root filesystem in GB.
*   `network_config`: The network configuration for the container, including interface name, bridge, IP address, and gateway.
*   `mac_address`: The MAC address for the container's network interface.
*   `gpu_assignment`: The GPU(s) to assign to the container (e.g., "0", "0,1", "none").
*   `portainer_role`: The Portainer role for the container (e.g., "server", "agent", "none").
*   `unprivileged`: (boolean) Whether the container should be unprivileged.
*   `clone_from_ctid`: The ID of the container to clone from.
*   `features`: An array of feature scripts to apply to the container (e.g., "base_setup", "docker", "nvidia").
*   `lxc_options`: An array of raw LXC options to apply to the container's configuration file.
*   `template_snapshot_name`: The name of the snapshot to create for template containers.
*   `apparmor_profile`: The AppArmor profile to apply to the container.
*   `apparmor_manages_nesting`: (boolean) Whether AppArmor should manage nesting for the container.
*   `application_script`: The application script to run in the container after provisioning.
*   `ports`: An array of ports to forward to the container (e.g., "8080:80").
*   `health_check`: The health check command to run in the container.
*   `firewall`: The firewall rules for the container.
*   `dependencies`: An array of container IDs that this container depends on.
*   `volumes`: An array of dedicated volumes to mount into the container.
*   `zfs_volumes`: An array of ZFS volumes to mount into the container.
*   `pct_options`: An array of `pct` options to apply to the container.
*   `tests`: Defines test suites for the container.
*   `vllm_model`: The vLLM model to be deployed (e.g., "Qwen/Qwen2.5-7B-Instruct-AWQ").
*   `vllm_quantization`: The quantization method for the vLLM model (e.g., "awq_marlin").
*   `vllm_max_model_len`: The maximum model length for vLLM.
*   `vllm_gpu_memory_utilization`: The GPU memory utilization for vLLM.
*   `vllm_tensor_parallel_size`: The tensor parallel size for vLLM.
*   `vllm_served_model_name`: The served model name for vLLM.
*   `vllm_model_type`: The model type for vLLM (e.g., "chat", "embedding").
*   `vllm_port`: The port for the vLLM service.
*   `vllm_trust_remote_code`: (boolean) Whether to trust remote code for the vLLM model.
*   `vllm_parameters`: An object containing additional vLLM parameters.
*   `vllm_args`: An array of command-line arguments for the vLLM service.

## 3. `phoenix_vm_configs.json`

This file contains the configurations for virtual machines (VMs), including default settings and specific configurations for each VM.

### Top-Level Keys

*   `vm_defaults`: An object containing default settings that apply to all VMs unless overridden.
    *   `template`: The default VM template to use.
    *   `cores`: The default number of CPU cores.
    *   `memory_mb`: The default amount of memory in MB.
    *   `disk_size_gb`: The default disk size in GB.
    *   `storage_pool`: The default storage pool for VM disks.
    *   `network_bridge`: The default network bridge.
*   `vms`: An array of objects, where each object defines a specific VM.

### VM Configuration (`vms[n]`)

*   `vmid`: The unique ID of the virtual machine.
*   `name`: The hostname of the VM.
*   `is_template`: (boolean) Whether this VM should be converted to a template after provisioning.
*   `template_image`: The cloud-init image to use for creating the VM.
*   `clone_from_vmid`: The ID of the VM template to clone from.
*   `template_snapshot_name`: The name of the snapshot to create for template VMs.
*   `cores`: The number of CPU cores to allocate to the VM.
*   `memory_mb`: The amount of memory to allocate to the VM in MB.
*   `disk_size_gb`: The size of the VM's disk in GB.
*   `storage_pool`: The storage pool to use for the VM's disk.
*   `network_bridge`: The network bridge to connect the VM to.
*   `features`: An array of feature scripts to apply to the VM (e.g., "docker").
*   `network_config`: The network configuration for the VM, including IP address, gateway, and nameservers.
*   `user_config`: The user configuration for the VM, including the default username.