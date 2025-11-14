# Portainer Admin User Creation - Firewall Troubleshooting Plan

This document outlines a comprehensive test plan to diagnose the suspected firewall issue preventing the successful creation of the Portainer admin user during the `phoenix sync all` process.

## Phase 1: Declarative Firewall Configuration Review

The first step is to conduct a thorough review of all declarative firewall rules defined in the project's JSON configuration files. This will establish a baseline of the intended firewall posture.

### 1.1. Hypervisor Firewall Rules (`phoenix_hypervisor_config.json`)
- **Objective:** Verify that the Proxmox host firewall is configured to allow the initial outbound request from the `portainer-manager.sh` script to the Nginx gateway.
- **Key Rule to Verify:**
  - `OUT ACCEPT from 10.0.0.13 to 10.0.0.153 on TCP port 443`

### 1.2. Nginx Gateway (LXC 101) Firewall Rules (`phoenix_lxc_configs.json`)
- **Objective:** Verify that the Nginx container allows the inbound request from the host and is permitted to make an outbound request to the Traefik container.
- **Key Rules to Verify:**
  - `IN ACCEPT from 10.0.0.13 on TCP port 443`
  - `OUT ACCEPT to 10.0.0.12 on TCP port 80`

### 1.3. Traefik (LXC 102) Firewall Rules (`phoenix_lxc_configs.json`)
- **Objective:** Verify that the Traefik container allows the inbound request from Nginx and is permitted to make an outbound request to the Portainer VM.
- **Key Rules to Verify:**
  - `IN ACCEPT from 10.0.0.153 on TCP port 80`
  - `OUT ACCEPT to 10.0.0.111 on TCP port 9443`

### 1.4. Portainer VM (VM 1001) Firewall Rules (`phoenix_vm_configs.json`)
- **Objective:** Verify that the Portainer VM allows the inbound request from the Traefik container.
- **Key Rule to Verify:**
  - `IN ACCEPT from 10.0.0.12 on TCP port 9443`

## Phase 2: Live Network Path Validation

This phase involves executing a series of commands on the live system to test the actual network path and validate that the declarative rules have been correctly applied.

### 2.1. Proxmox Host to Nginx Gateway (LXC 101)
- **Objective:** Confirm DNS resolution and basic connectivity from the host to the Nginx gateway.
- **Test Commands:**
  ```bash
  # 1. Test DNS Resolution
  nslookup portainer.internal.thinkheads.ai

  # 2. Test Connectivity (should fail handshake but prove connectivity)
  curl -v --insecure https://10.0.0.153
  ```

### 2.2. Nginx Gateway (LXC 101) to Traefik (LXC 102)
- **Objective:** Confirm connectivity from the Nginx container to the Traefik container.
- **Test Command (to be run inside LXC 101):**
  ```bash
  pct exec 101 -- curl -v http://10.0.0.12
  ```

### 2.3. Traefik (LXC 102) to Portainer VM (VM 1001)
- **Objective:** Confirm connectivity from the Traefik container to the Portainer VM.
- **Test Command (to be run inside LXC 102):**
  ```bash
  pct exec 102 -- curl -v --insecure https://10.0.0.111:9443
  ```

## Phase 3: Certificate and TLS Validation

This phase will verify that the TLS certificates are correctly issued and presented at each hop, which is a common point of failure in secure communication chains.

### 3.1. Nginx Gateway Certificate
- **Objective:** Verify the certificate presented by Nginx.
- **Test Command (from Proxmox Host):**
  ```bash
  openssl s_client -connect 10.0.0.153:443 -servername portainer.internal.thinkheads.ai
  ```

### 3.2. Portainer Certificate
- **Objective:** Verify the certificate presented by the Portainer service.
- **Test Command (from inside LXC 102):**
  ```bash
  pct exec 102 -- openssl s_client -connect 10.0.0.111:9443 -servername portainer.internal.thinkheads.ai
  ```

## Summary

By executing this plan, we will have a clear and definitive answer as to where the communication breakdown is occurring. The results of these tests will guide the necessary remediation steps, whether they involve correcting a firewall rule, fixing a DNS entry, or reissuing a certificate.