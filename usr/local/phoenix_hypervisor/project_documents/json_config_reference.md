# JSON Configuration Reference

This document provides a comprehensive reference for the JSON configuration files used in the Phoenix Hypervisor project.

## `phoenix_hypervisor_config.json`

This file contains the global configuration settings for the Phoenix Hypervisor.

### `hypervisor`

| Key | Type | Description |
| --- | --- | --- |
| `admin_user` | String | The username of the administrative user on the Proxmox host. |
| `admin_password` | String | The password for the administrative user. |
| `storage_pool` | String | The name of the ZFS storage pool to be used for containers and VMs. |
| `nfs_share` | String | The path to the NFS share to be mounted on the Proxmox host. |
| `samba_share` | String | The path to the Samba share to be mounted on the Proxmox host. |

### `features`

| Key | Type | Description |
| --- | --- | --- |
| `zfs` | Boolean | Enable or disable ZFS support. |
| `nfs` | Boolean | Enable or disable NFS support. |
| `samba` | Boolean | Enable or disable Samba support. |
| `nvidia` | Boolean | Enable or disable NVIDIA driver installation. |
| `docker` | Boolean | Enable or disable Docker installation. |
| `vllm` | Boolean | Enable or disable vLLM installation. |

## `phoenix_lxc_configs.json`

This file contains the configuration settings for individual LXC containers.

### `containers`

This is an array of container objects, each with the following properties:

| Key | Type | Description |
| --- | --- | --- |
| `ctid` | Integer | The ID of the container. |
| `hostname` | String | The hostname of the container. |
| `template` | String | The name of the template to be used for creating the container. |
| `clone_from_ctid` | Integer | The ID of the container to be cloned. |
| `cores` | Integer | The number of CPU cores to be allocated to the container. |
| `memory` | Integer | The amount of memory (in MB) to be allocated to the container. |
| `storage` | String | The amount of storage (in GB) to be allocated to the container. |
| `ip` | String | The IP address of the container. |
| `gateway` | String | The gateway address for the container. |
| `features` | Array | An array of features to be installed in the container. |
| `application_script` | String | The path to the application script to be executed in the container. |