# Dual-Horizon DNS Verification Commands

## Objective
Verify that the dual-horizon DNS is correctly resolving hostnames for both external and internal zones, as defined in `phoenix_hypervisor_config.json`.

## Commands to be executed on the Proxmox Host

1.  **Query External Zone:**
    *   **Purpose:** Verifies that the external hostname `portainer.phoenix.thinkheads.ai` resolves to the public-facing IP of the Nginx gateway (`10.0.0.153`).
    *   **Command:**
        ```bash
        dig @127.0.0.1 portainer.phoenix.thinkheads.ai +short | grep -q "10.0.0.153" && echo "SUCCESS: External DNS resolves correctly." || echo "FAILURE: External DNS resolution is incorrect."
        ```

2.  **Query Internal Zone:**
    *   **Purpose:** Verifies that the internal hostname `portainer.internal.thinkheads.ai` resolves to the direct internal IP of the Portainer VM (`10.0.0.101`).
    *   **Command:**
        ```bash
        dig @127.0.0.1 portainer.internal.thinkheads.ai +short | grep -q "10.0.0.101" && echo "SUCCESS: Internal DNS resolves correctly from host." || echo "FAILURE: Internal DNS resolution from host is incorrect."
        ```

## Commands to be executed inside VM 1001

1.  **Verify `/etc/resolv.conf`:**
    *   **Purpose:** Ensures that VM 1001 is configured to use the Proxmox host (`10.0.0.13`) as its primary nameserver.
    *   **Command:**
        ```bash
        grep -q "nameserver 10.0.0.13" /etc/resolv.conf && echo "SUCCESS: VM is using the correct nameserver." || echo "FAILURE: VM is not using the correct nameserver."
        ```

2.  **Query Internal Zone from VM:**
    *   **Purpose:** Confirms that from within the VM, the internal hostname resolves to the correct internal IP. This is the most critical test for service-to-service communication.
    *   **Command:**
        ```bash
        dig portainer.internal.thinkheads.ai +short | grep -q "10.0.0.101" && echo "SUCCESS: Internal DNS resolves correctly from VM." || echo "FAILURE: Internal DNS resolution from VM is incorrect."