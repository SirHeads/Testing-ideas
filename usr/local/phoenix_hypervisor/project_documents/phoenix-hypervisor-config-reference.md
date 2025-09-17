# Phoenix Hypervisor Configuration Reference

## Introduction

This document provides a detailed reference for the `phoenix_hypervisor_config.json` file. This file is the central configuration for the Phoenix Hypervisor system, controlling various aspects of the hypervisor, virtual machines, containers, storage, and networking.

**Location:** `/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json`

---

## Table of Contents

- [Top-Level Configuration](#top-level-configuration)
- [Users](#users)
- [Core Paths](#core-paths)
- [Network](#network)
- [Docker](#docker)
- [NFS](#nfs)
- [Samba](#samba)
- [ZFS](#zfs)
- [Proxmox Storage IDs](#proxmox-storage-ids)
- [Mount Point Base](#mount-point-base)
- [Proxmox Defaults](#proxmox-defaults)
- [VM Defaults](#vm-defaults)
- [VMs](#vms)
- [NVIDIA Driver](#nvidia-driver)
- [Behavior](#behavior)
- [Shared Volumes](#shared-volumes)

---

## Top-Level Configuration

These are the main keys at the root of the configuration file.

| Key       | Type   | Description                                      |
| :-------- | :----- | :----------------------------------------------- |
| `version` | String | The version of the configuration file format.    |
| `author`  | String | The author(s) of the configuration file.         |
| `users`   | Object | Defines user account settings for the hypervisor. |
| `core_paths`| Object | Defines critical file paths used by the system. |
| `timezone`| String | The timezone for the hypervisor.                 |
| `network` | Object | Network configuration for the hypervisor.        |
| `docker`  | Object | Docker-related configurations.                   |
| `nfs`     | Object | NFS server export configurations.                |
| `samba`   | Object | Samba share configurations.                      |
| `zfs`     | Object | ZFS storage pool and dataset configurations.     |
| `proxmox_storage_ids` | Object | Proxmox storage identifiers.          |
| `mount_point_base` | String | The base path for Proxmox mount points.  |
| `proxmox_defaults` | Object | Default settings for Proxmox LXC containers. |
| `vm_defaults` | Object | Default settings for virtual machines.       |
| `vms`     | Array  | A list of virtual machine definitions.           |
| `nvidia_driver` | Object | NVIDIA driver installation settings.       |
| `behavior`| Object | Defines system behavior on certain events.       |
| `shared_volumes` | Object | Defines shared volumes and their mount points. |

---

## Users

The `users` object contains settings for the primary administrative user.

| Key              | Type    | Description                                      |
| :--------------- | :------ | :----------------------------------------------- |
| `username`       | String  | The username for the administrative account.     |
| `password_hash`  | String  | The hashed password for the user. "NOT_SET" if not configured. |
| `sudo_access`    | Boolean | If `true`, the user has sudo privileges.         |
| `ssh_public_key` | String  | The public SSH key for the user.                 |

---

## Core Paths

The `core_paths` object defines the locations of essential configuration and data files.

| Key                      | Type   | Description                                      |
| :----------------------- | :----- | :----------------------------------------------- |
| `lxc_config_file`        | String | Path to the LXC container configuration file.    |
| `lxc_config_schema_file` | String | Path to the schema for the LXC configuration file. |
| `hf_token_file`          | String | Path to the Hugging Face token file.             |
| `docker_token_file`      | String | Path to the Docker token file.                   |
| `docker_images_path`     | String | Path to the directory for Docker images.         |
| `hypervisor_marker_dir`  | String | Path to the directory for the hypervisor marker file. |
| `hypervisor_marker`      | String | Path to the marker file indicating initialization. |

---

## Network

The `network` object configures the hypervisor's network settings.

| Key                   | Type   | Description                                      |
| :-------------------- | :----- | :----------------------------------------------- |
| `external_registry_url` | String | The URL of the external Docker registry.         |
| `portainer_server_ip` | String | The IP address of the Portainer server.          |
| `portainer_server_port` | Number | The port for the Portainer server.               |
| `portainer_agent_port`| Number | The port for the Portainer agent.                |
| `interfaces`          | Object | Network interface configuration.                 |
| `default_subnet`      | String | The default subnet for the network.              |
| `nfs_server`          | String | The IP address of the NFS server.                |

### Interfaces

| Key               | Type   | Description                                      |
| :---------------- | :----- | :----------------------------------------------- |
| `name`            | String | The name of the network interface (e.g., `vmbr0`). |
| `address`         | String | The IP address and subnet mask (e.g., `10.0.0.13/24`). |
| `gateway`         | String | The network gateway address.                     |
| `dns_nameservers` | String | The DNS nameserver address.                      |

---

## Docker

The `docker` object specifies the Docker images to be used.

| Key                      | Type   | Description                                      |
| :----------------------- | :----- | :----------------------------------------------- |
| `portainer_server_image` | String | The Docker image for the Portainer server.       |
| `portainer_agent_image`  | String | The Docker image for the Portainer agent.        |

---

## NFS

The `nfs` object is for configuring NFS exports.

| Key       | Type  | Description                                      |
| :-------- | :---- | :----------------------------------------------- |
| `exports` | Array | An array of NFS export definitions. (Currently empty) |

---

## Samba

The `samba` object configures Samba shares.

| Key      | Type   | Description                                      |
| :------- | :----- | :----------------------------------------------- |
| `user`   | String | The default user for Samba shares.               |
| `shares` | Array  | An array of Samba share definitions.             |

### Samba Shares

Each object in the `shares` array defines a Samba share.

| Key         | Type   | Description                                      |
| :---------- | :----- | :----------------------------------------------- |
| `name`      | String | The name of the Samba share.                     |
| `path`      | String | The path to the directory to be shared.          |
| `options`   | String | Samba share options (e.g., `browseable=yes`).    |
| `valid_users` | Array  | A list of users who can access the share.      |

---

## ZFS

The `zfs` object configures ZFS storage pools and datasets.

| Key        | Type   | Description                                      |
| :--------- | :----- | :----------------------------------------------- |
| `arc_max_gb` | Number | The maximum size in GB for the ZFS ARC cache.    |
| `pools`    | Array  | An array of ZFS pool definitions.                |
| `datasets` | Array  | An array of ZFS dataset definitions.             |

### ZFS Pools

| Key          | Type   | Description                                      |
| :----------- | :----- | :----------------------------------------------- |
| `name`       | String | The name of the ZFS pool.                        |
| `raid_level` | String | The RAID level for the pool (e.g., `mirror`).    |
| `disks`      | Array  | A list of disk identifiers for the pool.         |

### ZFS Datasets

| Key                    | Type   | Description                                      |
| :--------------------- | :----- | :----------------------------------------------- |
| `name`                 | String | The name of the dataset.                         |
| `pool`                 | String | The ZFS pool where the dataset resides.          |
| `properties`           | String | ZFS properties for the dataset.                  |
| `proxmox_storage_type` | String | The Proxmox storage type (e.g., `zfspool`, `dir`). |
| `proxmox_content_type` | String | The content type for Proxmox (e.g., `images`).   |

---

## Proxmox Storage IDs

The `proxmox_storage_ids` object maps friendly names to Proxmox storage identifiers.

| Key               | Type   | Description                                      |
| :---------------- | :----- | :----------------------------------------------- |
| `quickos_vm`      | String | Storage ID for VM disks on the `quickOS` pool.   |
| `quickos_lxc`     | String | Storage ID for LXC disks on the `quickOS` pool.  |
| `fastdata_backup` | String | Storage ID for backups on the `fastData` pool.   |
| `fastdata_iso`    | String | Storage ID for ISOs on the `fastData` pool.      |

---

## Mount Point Base

| Key                | Type   | Description                                      |
| :----------------- | :----- | :----------------------------------------------- |
| `mount_point_base` | String | The base directory for Proxmox mount points.     |

---

## Proxmox Defaults

The `proxmox_defaults` object specifies default settings for LXC containers.

| Key            | Type   | Description                                      |
| :------------- | :----- | :----------------------------------------------- |
| `zfs_lxc_pool` | String | The default ZFS pool for LXC containers.         |
| `lxc`          | Object | Default settings for LXC containers.             |

### LXC Defaults

| Key              | Type   | Description                                      |
| :--------------- | :----- | :----------------------------------------------- |
| `cores`          | Number | Default number of CPU cores for an LXC.          |
| `memory_mb`      | Number | Default memory in MB for an LXC.                 |
| `network_config` | String | Default network configuration for an LXC.        |
| `features`       | String | Default features for an LXC (e.g., `nesting=1`). |
| `security`       | String | Default security settings for an LXC.            |
| `nesting`        | Number | Default nesting setting for an LXC.              |

---

## VM Defaults

The `vm_defaults` object specifies default settings for virtual machines.

| Key              | Type   | Description                                      |
| :--------------- | :----- | :----------------------------------------------- |
| `template`       | String | The default VM template to use.                  |
| `cores`          | Number | Default number of CPU cores for a VM.            |
| `memory_mb`      | Number | Default memory in MB for a VM.                   |
| `disk_size_gb`   | Number | Default disk size in GB for a VM.                |
| `storage_pool`   | String | The default storage pool for a VM.               |
| `network_bridge` | String | The default network bridge for a VM.             |

---

## VMs

The `vms` array contains definitions for specific virtual machines.

| Key                   | Type   | Description                                      |
| :-------------------- | :----- | :----------------------------------------------- |
| `name`                | String | The name of the VM.                              |
| `cores`               | Number | The number of CPU cores for the VM.              |
| `memory_mb`           | Number | The memory in MB for the VM.                     |
| `disk_size_gb`        | Number | The disk size in GB for the VM.                  |
| `post_create_scripts` | Array  | A list of scripts to run after VM creation.      |

---

## NVIDIA Driver

The `nvidia_driver` object configures the installation of NVIDIA drivers.

| Key                 | Type    | Description                                      |
| :------------------ | :------ | :----------------------------------------------- |
| `install`           | Boolean | If `true`, the NVIDIA driver will be installed.  |
| `version`           | String  | The version of the NVIDIA driver to install.     |
| `runfile_url`       | String  | The URL to the NVIDIA driver runfile.            |
| `cuda_version`      | String  | The version of CUDA to install.                  |
| `install_vllm_libs` | Boolean | If `true`, VLLM libraries will be installed.     |

---

## Behavior

The `behavior` object controls system actions in specific scenarios.

| Key                 | Type    | Description                                      |
| :------------------ | :------ | :----------------------------------------------- |
| `rollback_on_failure` | Boolean | If `true`, the system will roll back on failure. |
| `debug_mode`        | Boolean | If `true`, debug mode is enabled.                |

---

## Shared Volumes

The `shared_volumes` object defines shared storage volumes and their mount points within containers.

Each key under `shared_volumes` represents a shared volume.

| Key         | Type   | Description                                      |
| :---------- | :----- | :----------------------------------------------- |
| `host_path` | String | The path to the shared volume on the host.       |
| `mounts`    | Object | An object mapping container IDs to mount paths.  |

### Firewall

The `firewall` object within `shared_volumes` configures the firewall.

| Key                     | Type    | Description                                      |
| :---------------------- | :------ | :----------------------------------------------- |
| `enabled`               | Boolean | If `true`, the firewall is enabled.              |
| `default_input_policy`  | String  | The default policy for incoming traffic (`DROP` or `ACCEPT`). |
| `default_output_policy` | String  | The default policy for outgoing traffic (`DROP` or `ACCEPT`). |