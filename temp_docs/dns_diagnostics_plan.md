# DNS Diagnostics Plan

This plan outlines the steps to diagnose and verify the DNS resolution within the Phoenix Hypervisor environment.

## Objective

To ensure that the `dnsmasq` service on the Proxmox host is correctly configured and that all key VMs and LXCs can resolve the hostnames of internal services.

## Verification Steps

The following commands should be executed to verify DNS resolution.

### 1. Verify `dnsmasq` Configuration on Proxmox Host

These commands should be run directly on the Proxmox host.

*   **Check `dnsmasq` service status:**
    ```bash
    systemctl status dnsmasq
    ```
*   **Verify the generated `dnsmasq` configuration:**
    ```bash
    cat /etc/dnsmasq.d/00-phoenix-internal.conf
    ```
*   **Test resolution of key services using `dig`:**
    ```bash
    dig @127.0.0.1 portainer.internal.thinkheads.ai
    dig @127.0.0.1 ca.internal.thinkheads.ai
    dig @127.0.0.1 traefik.internal.thinkheads.ai
    ```

### 2. Verify DNS Resolution from within Key LXCs

These commands should be run from within the specified LXCs using `pct exec`.

*   **From LXC 101 (Nginx):**
    ```bash
    pct exec 101 -- dig ca.internal.thinkheads.ai
    pct exec 101 -- dig traefik.internal.thinkheads.ai
    ```
*   **From LXC 102 (Traefik):**
    ```bash
    pct exec 102 -- dig ca.internal.thinkheads.ai
    pct exec 102 -- dig portainer.internal.thinkheads.ai
    ```
*   **From LXC 103 (Step-CA):**
    ```bash
    pct exec 103 -- dig portainer.internal.thinkheads.ai
    ```

### 3. Verify DNS Resolution from within Key VMs

These commands should be run from within the specified VMs using `qm guest exec`.

*   **From VM 1001 (Portainer):**
    ```bash
    qm guest exec 1001 -- dig ca.internal.thinkheads.ai
    qm guest exec 1001 -- dig drphoenix.internal.thinkheads.ai
    ```
*   **From VM 1002 (drphoenix):**
    ```bash
    qm guest exec 1002 -- dig portainer.internal.thinkheads.ai
    ```

## Expected Outcomes

*   All `dig` commands should return a `status: NOERROR` and an `ANSWER SECTION` containing the correct IP address for the queried hostname.
*   The IP addresses should match the ones defined in the `phoenix_lxc_configs.json` and `phoenix_vm_configs.json` files.

Any failures in these checks will indicate a problem with the `dnsmasq` configuration, the network configuration of the guest, or the firewall rules preventing DNS queries.