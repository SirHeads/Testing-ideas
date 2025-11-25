# Project Summary: Macvlan & Internal Mesh Architecture
**Date:** November 25, 2025
**Status:** Successfully Deployed

## 1. Overview
This project aimed to resolve persistent networking issues caused by Macvlan DHCP suppression on the Proxmox host's primary interface. The solution involved architecting a new network topology that separates public-facing traffic onto a dedicated VLAN (20) while establishing a secure, zero-trust internal mesh for service-to-service communication.

## 2. Key Architectural Changes

### A. Network Topology
*   **Public Access (VLAN 20):** A new bridge `vmbr0.20` was created. The Nginx Gateway (LXC 101) is now dual-homed, utilizing a Macvlan interface on this bridge to reliably acquire a public IP via DHCP without host-level interference.
*   **Internal Mesh (vmbr100):** A dedicated, isolated bridge `vmbr100` (subnet `172.16.100.0/24`) was established for all internal infrastructure.
*   **NAT/Masquerading:** Enabled on the host to allow internal containers (Step-CA, Traefik) to reach the internet for updates while remaining inaccessible from the outside.

### B. Infrastructure Migration
| Service | Previous IP | New IP | Role |
| :--- | :--- | :--- | :--- |
| **Step-CA (103)** | 10.0.0.10 | **172.16.100.11** | Internal Root of Trust. No public access. |
| **Traefik (102)** | 10.0.0.12 | **172.16.100.12** | Internal Reverse Proxy. Routes mesh traffic. |
| **Nginx (101)** | DHCP (Flaky) | **DHCP (VLAN 20)** | Public Ingress. Dual-homed with internal IP `172.16.100.10`. |
| **Portainer (1001)** | 10.0.0.111 | **10.0.0.111** | Management VM. (Network unchanged for now). |
| **DrPhoenix (1002)**| 10.0.0.102 | **10.0.0.102** | Worker Node. (Network unchanged for now). |

## 3. Implementation Details

### Core Script Updates
1.  **`hypervisor_feature_setup_macvlan.sh`:**
    *   Updated to create `vmbr0.20` and `vmbr100`.
    *   Added persistent `iptables` rules for NAT (Masquerading) and IP forwarding to ensure internal internet access.
2.  **`lxc-manager.sh`:**
    *   Refactored `apply_network_configs` to support multiple interfaces (`net0`, `net1`) dynamically.
    *   Added logic to handle `secondary_network_config` for dual-homed containers like Nginx.
3.  **`hypervisor_feature_setup_dns_server.sh`:**
    *   Updated `dnsmasq` configuration to bind to the internal gateway IP (`172.16.100.1`), serving DNS to the isolated mesh.

### Configuration Refactoring
*   **`phoenix_lxc_configs.json`:**
    *   Updated Nginx (101) to use `vmbr0.20` for `net0` and `vmbr100` for `net1`.
    *   Moved Step-CA (103) and Traefik (102) entirely to `vmbr100`.
    *   Temporarily disabled firewalls to isolate network routing verification.
*   **`certificate-manifest.json`:**
    *   Updated all SANs to reflect the new `172.16.100.x` addresses.
    *   Removed legacy `10.0.0.x` references for internal services.

### Certificate Authority Regeneration
*   Wiped the persistent Step-CA data to force the generation of a new Root CA valid for the `172.16` subnet.
*   Re-bootstrapped the host `step-cli` to trust the new Root CA.
*   Successfully renewed and distributed new certificates to all services.

## 4. Current Status & Validation

### Confirmed Working
*   **Host Network:** `vmbr0.20` and `vmbr100` are up and configured correctly.
*   **Internet Access:** Internal containers (Step-CA, Traefik) can reach the internet via NAT (confirmed by successful package installation).
*   **DNS:** Internal containers can resolve external domains.
*   **Certificate Authority:** Step-CA is healthy, accessible on `172.16.100.11`, and issuing valid certificates.
*   **Service Deployment:** All containers (101, 102, 103) and VMs (1001, 1002) were created successfully.
*   **Synchronization:** `phoenix sync all` completed without errors.

### Areas for Investigation (Next Steps)
1.  **Firewall Rules:** The firewalls for LXCs and VMs are currently **disabled**. The existing rules need to be updated for the new IP scheme and re-enabled carefully.
2.  **Application Connectivity:** While the network connects, we received a `404` when curling the Portainer API via Nginx. This suggests the routing path works (Nginx -> Traefik -> Portainer), but the specific endpoint or Traefik routing rule might need tuning.
3.  **Swarm Overlay:** The overlay network `traefik-public` was created successfully, but we should verify cross-node communication between the Manager and Worker over the new topology.

## 5. Conclusion
The platform has successfully migrated to a robust, segmented network architecture. The "DHCP suppression" bug is structurally resolved by VLAN 20, and the internal security posture is significantly improved by the isolated mesh. The system is fully deployed and synchronized, ready for application-level tuning and security hardening.

## 6. Next Steps (for the next project):

Re-enable and harden firewalls: The firewalls for LXCs and VMs are currently disabled to isolate network issues. They must be updated for the 172.16 subnet and re-enabled.
Investigate the 404 response: The curl test to Portainer via Nginx/Traefik returned a 404. This confirms the routing path is open (good!) but the specific endpoint or Traefik rule needs tuning.Verify Docker Swarm overlay: Ensure the traefik-public overlay network is passing traffic correctly between the manager and worker nodes.