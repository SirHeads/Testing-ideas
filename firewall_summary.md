# Phoenix Hypervisor Firewall Rule Summary

This document provides a comprehensive summary of all firewall rules defined within the Phoenix Hypervisor ecosystem. The rules are managed declaratively through the `phoenix_hypervisor_config.json` and `phoenix_lxc_configs.json` files.

## 1. Global Firewall Rules

These rules are applied at the hypervisor level and govern traffic for the entire system.

| Direction | Action | Protocol | Port | Source | Destination | Comment |
|---|---|---|---|---|---|---|
| In | ACCEPT | tcp | 80 | any | any | Allow HTTP traffic to Nginx gateway |
| In | ACCEPT | tcp | 443 | any | any | Allow HTTPS traffic to Nginx gateway |
| In | ACCEPT | tcp | 9001 | any | 10.0.0.102 | Allow Portainer agent communication |
| In | ACCEPT | tcp | 2049 | any | any | Allow NFS traffic |
| In | ACCEPT | udp | 2049 | any | any | Allow NFS traffic |
| In | ACCEPT | tcp | 111 | any | any | Allow rpcbind traffic |
| In | ACCEPT | udp | 111 | any | any | Allow rpcbind traffic |
| In | ACCEPT | tcp | 139 | any | any | Allow Samba NetBIOS |
| In | ACCEPT | tcp | 445 | any | any | Allow Samba SMB |
| In | ACCEPT | udp | 137 | any | any | Allow Samba NetBIOS Name Service |
| In | ACCEPT | udp | 138 | any | any | Allow Samba NetBIOS Datagram Service |
| Out | ACCEPT | udp | 53 | 10.0.0.0/24 | 0.0.0.0/0 | Allow outbound DNS traffic from all guests |
| Out | ACCEPT | tcp | 53 | 10.0.0.0/24 | 0.0.0.0/0 | Allow outbound DNS traffic (TCP) from all guests |

## 2. LXC Container Firewall Rules

These rules are applied to individual LXC containers.

### CTID 101: Nginx-Phoenix

| Direction | Action | Protocol | Port | Source | Destination |
|---|---|---|---|---|---|
| In | ACCEPT | tcp | 80 | any | any |
| In | ACCEPT | tcp | 443 | any | any |
| Out | ACCEPT | tcp | 9443 | any | 10.0.0.101 |

### CTID 102: Traefik-Internal

| Direction | Action | Protocol | Port | Source | Destination |
|---|---|---|---|---|---|
| In | ACCEPT | tcp | 443 | 10.0.0.153 | any |
| In | ACCEPT | tcp | 80 | 10.0.0.153 | any |

### CTID 801: granite-embedding

| Direction | Action | Protocol | Port | Source | Destination |
|---|---|---|---|---|---|
| In | ACCEPT | tcp | 8000 | 10.0.0.153 | any |
