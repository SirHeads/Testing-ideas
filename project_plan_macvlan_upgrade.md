# Project Plan: Phoenix Macvlan Architecture Upgrade (Approved & Refined)

## 1. Objective
Upgrade the networking architecture of the Phoenix Hypervisor to support **Macvlan** networking for LXC containers. This will allow specific containers (initially the Nginx Gateway, LXC 101) to attach directly to the physical LAN with their own public IP addresses, eliminating the need for host-level NAT and iptables port forwarding.

## 2. Scope
This project involves updates to the declarative configuration schema and the associated manager scripts to support a dual-interface network topology (Internal Bridge + Public Macvlan).

**Target Services:**
*   **LXC 101 (Nginx Gateway):** Primary candidate for public exposure.

**Affected Components:**
1.  `phoenix_hypervisor_config.json` (Global settings)
2.  `phoenix_lxc_configs.json` (Container definitions)
3.  `lxc-manager.sh` (Orchestration logic)
4.  `phoenix_hypervisor_lxc_101.sh` (Nginx configuration)
5.  `hypervisor_feature_setup_firewall.sh` (Security automation)

## 3. Technical Specifications

### 3.1. Configuration Schema Updates

#### A. Global Configuration (`phoenix_hypervisor_config.json`)
We need to explicitly define the physical network interface bridge that Macvlan will attach to.

*   **New Field:** `network.public_bridge`
*   **Value:** `"vmbr0"` (The bridge connected to the physical uplink).

#### B. LXC Configuration (`phoenix_lxc_configs.json`)
We will add a `public_interface` object to the LXC definition.

```json
"101": {
    "name": "Nginx-Phoenix",
    ...
    "network_config": { ... }, // Existing internal config (net0)
    "public_interface": {      // New Macvlan config (net1)
        "enabled": true,
        "type": "macvlan",      // "macvlan" (bridge mode) or "ipvlan" (L3 mode - future proofing)
        "mode": "bridge",       // only needed for macvlan
        "ip": "192.168.1.153/24",
        "gw": "192.168.1.1", 
        "mac_address": "02:00:00:00:01:01" // Declarative MAC for static DHCP reservations
    }
}
```

### 3.2. LXC Manager Logic (`lxc-manager.sh`)

The `apply_network_configs` function will be enhanced to:
1.  Read the `public_bridge` from the global config.
2.  Check if `public_interface.enabled` is true for the target CTID.
3.  **Validation:** Verify that the chosen public IP is in the same subnet as `vmbr0` using `ip route get`.
4.  If enabled and valid, construct the `net1` configuration string for Proxmox using the **correct syntax**:
    *   **Format:** `name=eth1,macaddr=<MAC>,bridge=<BRIDGE>,type=macvlan,mode=bridge,ip=<IP>,gw=<GW>`
5.  Apply the configuration using `pct set <CTID> --net1 ...`.

### 3.3. Nginx Configuration (`phoenix_hypervisor_lxc_101.sh`)

The Nginx setup script needs to bind to `0.0.0.0` (all interfaces) instead of a specific internal IP. We will implement an **idempotent helper function** inside the container to handle this configuration safely.

*   **Action:** Execute a helper command `nginx-config-set-listen-all-interfaces` inside the container.
*   **Logic:** Use `perl` or `sed` to safely replace `listen <IP>:443` with `listen 443` (or `listen [::]:443`) in `/etc/nginx/sites-available/gateway`, ensuring it works regardless of current state.

### 3.4. Firewall Automation (`hypervisor_feature_setup_firewall.sh`)

The firewall generator currently creates rules based on the assumption of a single internal interface. It needs to be updated to:
1.  Detect the presence of a public interface definition.
2.  If present, generate specific `ACCEPT` rules for traffic arriving on `eth1` (Public) for ports 80 and 443.
3.  Ensure these rules are applied to the guest-level firewall (`/etc/pve/firewall/<CTID>.fw`).

## 4. Implementation Plan

### Phase 1: Configuration
1.  **Identify Physical Interface:** Confirm the physical network interface on the host (likely `enp6s0`).
2.  **Update Global Config:** Add `public_bridge` to `phoenix_hypervisor_config.json`.
3.  **Update LXC Config:** Add the `public_interface` block to LXC 101 in `phoenix_lxc_configs.json` with the reserved IP (`192.168.1.153`).

### Phase 2: Logic Implementation
4.  **Modify `lxc-manager.sh`:** Implement the logic to parse and apply the `net1` Macvlan configuration with validation.
5.  **Modify `phoenix_hypervisor_lxc_101.sh`:** Add the logic to update Nginx listen directives.
6.  **Modify `hypervisor_feature_setup_firewall.sh`:** Update rule generation to support the new public interface profile.

### Phase 3: Deployment & Verification
7.  **Re-apply Configurations:** Run `phoenix create 101` (or a targeted config apply function) to attach the new interface.
8.  **Verify Connectivity:**
    *   Check `ip addr` inside LXC 101 to confirm `eth1` exists with the correct IP.
    *   Attempt to `curl` the public IP from an external machine on the LAN.
9.  **Cleanup:** Remove the obsolete `iptables` NAT rules from the Proxmox host.

## 5. Verification Checklist
- [ ] LXC 101 has `eth1` with IP `192.168.1.153`.
- [ ] `eth1` uses the declared MAC address.
- [ ] Nginx is listening on `0.0.0.0:443` (all interfaces).
- [ ] Public DNS `*.thinkheads.ai` resolves to `192.168.1.153`.
- [ ] External traffic reaches Nginx without host-level NAT.
- [ ] Internal traffic (Traefik, Swarm) continues to flow over `eth0` (`10.0.0.x`).