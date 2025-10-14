# Firewall Audit Report

## 1. Executive Summary

This report details the firewall architecture and rule-set for the Phoenix Hypervisor environment. The system utilizes Proxmox's built-in firewall (`pve-firewall`), managed through a declarative, Infrastructure-as-Code (IaC) approach. All firewall rules are defined in the central JSON configuration files, ensuring a single source of truth and enabling automated, idempotent application of the security policy.

## 2. Architecture Overview

The firewall management is orchestrated by the `phoenix-cli` tool, which applies rules defined in two key files:

*   **`phoenix_hypervisor_config.json`**: Contains the `global_firewall_rules` that apply to the entire Proxmox cluster. This includes baseline rules for essential services like SSH, NFS, and Samba, as well as default policies for inbound and outbound traffic.
*   **`phoenix_lxc_configs.json`**: Defines container-specific firewall rules. Each container configuration can have its own `firewall` object specifying a set of rules that apply only to that container.

The `hypervisor_feature_setup_firewall.sh` script, executed during the `phoenix-cli setup` process, is responsible for reading these configurations and writing them to the Proxmox firewall configuration file at `/etc/pve/firewall/cluster.fw`.

This declarative model ensures that the firewall state is version-controlled, auditable, and consistently applied across the environment.

## 3. Firewall Rule Inventory

This section will provide a detailed inventory of all firewall rules, categorized by their scope (global or container-specific).

### 3.1. Global Firewall Rules

The following rules are applied to the entire Proxmox cluster and are defined in `phoenix_hypervisor_config.json`. The default policy is to **DROP** all incoming traffic and **ACCEPT** all outgoing traffic.

| Direction | Action | Protocol | Port | Source/Destination | Comment |
|---|---|---|---|---|---|
| In | ACCEPT | tcp | 80 | - | Allow HTTP traffic to Nginx gateway |
| In | ACCEPT | tcp | 443 | - | Allow HTTPS traffic to Nginx gateway |
| In | ACCEPT | tcp | 9001 | dest=10.0.0.102 | Allow Portainer agent communication |
| In | ACCEPT | tcp | 2049 | - | Allow NFS traffic |
| In | ACCEPT | udp | 2049 | - | Allow NFS traffic |
| In | ACCEPT | tcp | 111 | - | Allow rpcbind traffic |
| In | ACCEPT | udp | 111 | - | Allow rpcbind traffic |
| In | ACCEPT | tcp | 139 | - | Allow Samba NetBIOS |
| In | ACCEPT | tcp | 445 | - | Allow Samba SMB |
| In | ACCEPT | udp | 137 | - | Allow Samba NetBIOS Name Service |
| In | ACCEPT | udp | 138 | - | Allow Samba NetBIOS Datagram Service |

### 3.2. Container-Specific Firewall Rules

The following rules are defined in `phoenix_lxc_configs.json` and apply to individual containers.

| CTID | Name | Direction | Action | Protocol | Port | Source/Destination |
|---|---|---|---|---|---|---|
| 801 | granite-embedding | In | ACCEPT | tcp | 8000 | source=10.0.0.153 |
| 101 | Nginx-Phoenix | In | ACCEPT | tcp | 80 | - |
| 101 | Nginx-Phoenix | In | ACCEPT | tcp | 443 | - |
| 101 | Nginx-Phoenix | Out | ACCEPT | tcp | 9443 | dest=10.0.0.101 |
| 102 | Traefik-Internal | In | ACCEPT | tcp | 443 | source=10.0.0.153 |
| 102 | Traefik-Internal | In | ACCEPT | tcp | 80 | source=10.0.0.153 |

## 4. Analysis and Recommendations

This section will analyze the effectiveness of the current firewall configuration and provide recommendations for potential improvements.

### 4.1. Strengths

*   **Declarative Management:** Managing firewall rules as code is a significant strength, providing auditability and reproducibility.
*   **Centralized Configuration:** All rules are defined in a central location, making it easy to understand the overall security posture.
*   **Idempotent Application:** The orchestration scripts ensure that the firewall rules are applied consistently and reliably.

### 4.2. Areas for Improvement

*   **Implicit Trust Model:** The current global firewall rules are quite permissive for services like NFS and Samba, allowing access from the entire `/24` subnet. While this is convenient for a single-node hypervisor, it represents an implicit trust model that could be hardened.
*   **Lack of Egress Filtering:** The default outbound policy is `ACCEPT`. While this is common, implementing egress filtering would provide an additional layer of security, preventing unauthorized outbound connections from compromised containers.
*   **Container-to-Container Traffic:** There are no explicit rules governing traffic between containers on the same bridge. All containers in the `10.0.0.0/24` subnet can communicate with each other unless a specific rule denies it.

### 4.3. Recommendations

*   **Implement a More Granular Trust Model:** For services like NFS and Samba, consider creating more specific rules that only allow access from the IP addresses of the VMs and containers that require it. This would reduce the attack surface if a container were to be compromised.
*   **Introduce Egress Filtering:** As a long-term goal, consider changing the default outbound policy to `DROP` and creating explicit `ACCEPT` rules for the outbound traffic that is required by each container. This would provide a significant security enhancement.
*   **Develop a Micro-segmentation Strategy:** For a higher level of security, consider implementing a micro-segmentation strategy that restricts communication between containers to only what is explicitly required. This could be achieved through a combination of more granular firewall rules and network segmentation.
