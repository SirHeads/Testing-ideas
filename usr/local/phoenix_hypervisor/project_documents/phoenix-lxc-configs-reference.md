# Phoenix LXC Configuration Reference

## Introduction

This document provides a detailed reference for the `phoenix_lxc_configs.json` file. This file is used to define the configurations for LXC containers managed by the Phoenix Hypervisor system.

**Location:** `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`

---

## Table of Contents

- [Top-Level Configuration](#top-level-configuration)
- [LXC Configurations (`lxc_configs`)](#lxc-configurations-lxc_configs)
- [Network Configuration (`network_config`)](#network-configuration-network_config)
- [Firewall (`firewall`)](#firewall-firewall)
- [Health Check (`health_check`)](#health-check-health_check)

---

## Top-Level Configuration

These are the main keys at the root of the configuration file.

| Key | Type | Description |
| :--- | :--- | :--- |
| `$schema` | String | The path to the JSON schema file that defines the structure of this configuration file. |
| `nvidia_driver_version` | String | The version of the NVIDIA driver to be used. |
| `nvidia_repo_url` | String | The URL of the NVIDIA repository. |
| `nvidia_runfile_url` | String | The URL to download the NVIDIA driver runfile. |
| `lxc_configs` | Object | Contains the configurations for all LXC containers, with each container's ID as the key. |

---

## LXC Configurations (`lxc_configs`)

The `lxc_configs` object contains a series of objects, each keyed by a unique container ID (e.g., "900", "950"). Each object defines the complete configuration for a single LXC container.

| Key | Type | Description |
| :--- | :--- | :--- |
| `name` | String | The hostname of the container. |
| `memory_mb` | Number | The amount of RAM in megabytes allocated to the container. |
| `cores` | Number | The number of CPU cores allocated to the container. |
| `template` | String | The path to the container template file. (Only for base templates) |
| `storage_pool` | String | The name of the storage pool where the container's disk will be created. |
| `storage_size_gb` | Number | The size of the container's disk in gigabytes. |
| `network_config` | Object | An object containing the network configuration for the container. See [Network Configuration](#network-configuration-network_config). |
| `mac_address` | String | The MAC address assigned to the container's network interface. |
| `gpu_assignment` | String | Specifies which GPU(s) to assign to the container. "none" for no GPU, or a comma-separated list of GPU IDs (e.g., "0,1"). |
| `portainer_role` | String | The role of the container in Portainer. Can be "server", "agent", "infrastructure", or "none". |
| `unprivileged` | Boolean | If `true`, the container is unprivileged. |
| `template_snapshot_name` | String | The name of the snapshot to create from a template container. |
| `clone_from_ctid` | String | The ID of the container to clone from. |
| `features` | Array | A list of features to enable for the container (e.g., "base_setup", "nvidia", "docker", "vllm", "ollama"). |
| `application_script` | String | The name of the script to run for application-specific setup. |
| `ports` | Array | A list of port mappings from host to container (e.g., "8000:8000"). |
| `vllm_model` | String | The vLLM model to be used. |
| `vllm_served_model_name` | String | The name under which the vLLM model is served. |
| `vllm_port` | Number | The port for the vLLM service. |
| `vllm_args` | Array | A list of additional arguments for the vLLM service. |
| `firewall` | Object | Firewall configuration for the container. See [Firewall](#firewall-firewall). |
| `dependencies` | Array | A list of container IDs that this container depends on. |
| `health_check` | Object | Health check configuration for the container. See [Health Check](#health-check-health_check). |
| `pct_options` | Array | A list of additional `pct` command options. |
| `swap_mb` | Number | The amount of swap space in megabytes allocated to the container. |

---

## Network Configuration (`network_config`)

The `network_config` object defines the network interface for a container.

| Key | Type | Description |
| :--- | :--- | :--- |
| `name` | String | The name of the network interface (e.g., `eth0`). |
| `bridge` | String | The bridge to connect the interface to (e.g., `vmbr0`). |
| `ip` | String | The IP address and subnet mask (e.g., `10.0.0.200/24`). |
| `gw` | String | The network gateway address. |

---

## Firewall (`firewall`)

The `firewall` object configures the firewall for a container.

| Key | Type | Description |
| :--- | :--- | :--- |
| `enabled` | Boolean | If `true`, the firewall is enabled for the container. |
| `rules` | Array | An array of firewall rule objects. |

### Firewall Rules

Each object in the `rules` array defines a firewall rule.

| Key | Type | Description |
| :--- | :--- | :--- |
| `type` | String | The direction of the traffic (e.g., `in`). |
| `action` | String | The action to take (`ACCEPT`, `DROP`, `REJECT`). |
| `source` | String | The source IP address or subnet. |
| `proto` | String | The protocol (`tcp`, `udp`). |
| `port` | String | The destination port. |

---

## Health Check (`health_check`)

The `health_check` object defines how to check if the container's application is running correctly.

| Key | Type | Description |
| :--- | :--- | :--- |
| `command` | String | The command to execute for the health check. |
| `retries` | Number | The number of times to retry the health check if it fails. |
| `interval` | Number | The interval in seconds between retries. |