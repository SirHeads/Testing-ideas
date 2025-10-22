# VM 1001 Verification Plan

## 1. Overview
This document provides a comprehensive set of commands to verify that VM 1001 has been correctly provisioned according to the declarative configuration in the Phoenix Hypervisor system.

The tests are divided into two main categories:
-   **Proxmox Host Commands:** To be run on the Proxmox hypervisor.
-   **VM 1001 Commands:** To be run inside the guest VM.

---

## 2. Proxmox Host Verification Commands

### 2.1. Firewall Verification
-   **List All Host Rules:** `pve-firewall rules`
-   **Verify HTTP/HTTPS Ingress:**
    ```bash
    pve-firewall rules | grep "ACCEPT.*dport 80" && echo "SUCCESS: HTTP rule found." || echo "FAILURE: HTTP rule missing."
    pve-firewall rules | grep "ACCEPT.*dport 443" && echo "SUCCESS: HTTPS rule found." || echo "FAILURE: HTTPS rule missing."
    ```
-   **Verify Default DROP Policy:** `pve-firewall status | grep "policy_in: DROP" && echo "SUCCESS: Default input policy is DROP." || echo "FAILURE: Default input policy is not DROP."`
-   **List VM 1001 Specific Rules:** `pve-firewall vmrules 1001`
-   **Verify VM 1001 Ingress Rules:**
    ```bash
    pve-firewall vmrules 1001 | grep "ACCEPT.*src 10.0.0.12.*dport 9443" && echo "SUCCESS: Traefik access rule found." || echo "FAILURE: Traefik access rule missing."
    pve-firewall vmrules 1001 | grep "ACCEPT.*src 10.0.0.13.*dport 9443" && echo "SUCCESS: Proxmox host access rule found." || echo "FAILURE: Proxmox host access rule missing."
    ```

### 2.2. DNS Verification
-   **Query External Zone:** `dig @127.0.0.1 portainer.phoenix.thinkheads.ai +short | grep -q "10.0.0.153" && echo "SUCCESS: External DNS resolves correctly." || echo "FAILURE: External DNS resolution is incorrect."`
-   **Query Internal Zone:** `dig @127.0.0.1 portainer.internal.thinkheads.ai +short | grep -q "10.0.0.101" && echo "SUCCESS: Internal DNS resolves correctly from host." || echo "FAILURE: Internal DNS resolution from host is incorrect."`

### 2.3. Traefik Integration Verification
-   **Query Traefik API for Portainer Service:**
    ```bash
    pct exec 102 -- bash -c "curl -s http://127.0.0.1:8080/api/http/services | jq -e '.[] | select(.name == \"portainer@file\" and .serverStatus.[\"https://10.0.0.101:9443\"] == \"UP\")'" && echo "SUCCESS: Traefik has discovered and configured the Portainer service correctly." || echo "FAILURE: Traefik has not discovered the Portainer service or it is misconfigured."
    ```
-   **Check Traefik Logs for Errors:** `pct exec 102 -- journalctl -u traefik.service --no-pager | grep "portainer" | grep "error" && echo "FAILURE: Errors found in Traefik logs related to Portainer." || echo "SUCCESS: No errors found in Traefik logs for Portainer."`

---

## 3. VM 1001 Guest Verification Commands

### 3.1. Step-CA Certificate Verification
-   **Verify Certificate Existence:** `[ -f /usr/local/share/ca-certificates/phoenix_ca.crt ] && echo "SUCCESS: CA certificate file found." || echo "FAILURE: CA certificate file is missing."`
-   **Verify Certificate Symlink:** `find /etc/ssl/certs -type l -exec readlink -f {} + | grep -q "/usr/local/share/ca-certificates/phoenix_ca.crt" && echo "SUCCESS: Certificate symlink is valid." || echo "FAILURE: Certificate symlink is missing or broken."`
-   **Verify Certificate Content:** `diff -q /usr/local/share/ca-certificates/phoenix_ca.crt /persistent-storage/.phoenix_scripts/phoenix_ca.crt && echo "SUCCESS: Certificate content matches source." || echo "FAILURE: Certificate content differs from source."`
-   **Verify with OpenSSL:** `openssl verify /usr/local/share/ca-certificates/phoenix_ca.crt`

### 3.2. DNS Verification
-   **Verify /etc/resolv.conf:** `grep -q "nameserver 10.0.0.13" /etc/resolv.conf && echo "SUCCESS: VM is using the correct nameserver." || echo "FAILURE: VM is not using the correct nameserver."`
-   **Query Internal Zone from VM:** `dig portainer.internal.thinkheads.ai +short | grep -q "10.0.0.101" && echo "SUCCESS: Internal DNS resolves correctly from VM." || echo "FAILURE: Internal DNS resolution from VM is incorrect."`

### 3.3. Portainer API Readiness
-   **Check Docker Container Status:** `docker ps --filter "name=portainer" --format "{{.Names}}" | grep -q "portainer" && echo "SUCCESS: Portainer container is running." || echo "FAILURE: Portainer container is not running."`
-   **Query Local Portainer API Endpoint:** `curl -sk https://localhost:9443/api/status | jq -e '.status == "UP"' && echo "SUCCESS: Portainer API is up and responsive." || echo "FAILURE: Portainer API is down or unresponsive."`