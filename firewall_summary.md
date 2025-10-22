# Firewall Verification Commands

## Part 1: Proxmox Host Firewall Verification

### Objective
Verify that the global firewall rules defined in `phoenix_hypervisor_config.json` are correctly applied to the Proxmox host.

### Commands to be executed on the Proxmox Host

1.  **List All Firewall Rules:**
    *   **Purpose:** Dumps all active firewall rules for the Proxmox host. This provides a complete picture that we can compare against our configuration.
    *   **Command:**
        ```bash
        pve-firewall rules
        ```

2.  **Verify Specific Ingress Rules:**
    *   **Purpose:** Checks for the presence of key ingress rules defined in the configuration.
    *   **Commands:**
        ```bash
        # Verify HTTP is allowed to Nginx Gateway
        pve-firewall rules | grep "ACCEPT.*dport 80" && echo "SUCCESS: HTTP rule found." || echo "FAILURE: HTTP rule missing."

        # Verify HTTPS is allowed to Nginx Gateway
        pve-firewall rules | grep "ACCEPT.*dport 443" && echo "SUCCESS: HTTPS rule found." || echo "FAILURE: HTTPS rule missing."

        # Verify internal ICMP is allowed
        pve-firewall rules | grep "ACCEPT.*icmp.*src 10.0.0.0/24" && echo "SUCCESS: Internal ICMP rule found." || echo "FAILURE: Internal ICMP rule missing."
        ```

3.  **Verify Default Input Policy:**
    *   **Purpose:** Confirms that the default policy for incoming traffic is `DROP`, as specified in the configuration for a secure-by-default posture.
    *   **Command:**
        ```bash
        pve-firewall status | grep "policy_in: DROP" && echo "SUCCESS: Default input policy is DROP." || echo "FAILURE: Default input policy is not DROP."
        ```

## Part 2: VM 1001 Firewall Verification

### Objective
Verify that the VM-specific firewall rules defined in `phoenix_vm_configs.json` are correctly applied to VM 1001.

### Commands to be executed on the Proxmox Host

1.  **List Firewall Rules for VM 1001:**
    *   **Purpose:** Dumps all active firewall rules specifically for VM 1001.
    *   **Command:**
        ```bash
        pve-firewall vmrules 1001
        ```

2.  **Verify Specific Ingress Rules for VM 1001:**
    *   **Purpose:** Checks for the presence of the rules that allow Traefik and the Proxmox host to access the Portainer API.
    *   **Commands:**
        ```bash
        # Verify Traefik access to Portainer
        pve-firewall vmrules 1001 | grep "ACCEPT.*src 10.0.0.12.*dport 9443" && echo "SUCCESS: Traefik access rule found." || echo "FAILURE: Traefik access rule missing."

        # Verify Proxmox host access to Portainer
        pve-firewall vmrules 1001 | grep "ACCEPT.*src 10.0.0.13.*dport 9443" && echo "SUCCESS: Proxmox host access rule found." || echo "FAILURE: Proxmox host access rule missing."
