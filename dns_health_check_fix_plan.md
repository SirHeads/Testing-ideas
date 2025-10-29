# DNS Health Check Fix Plan

This document outlines the plan to fix the failing DNS health check in the `portainer-manager.sh` script.

### 1. Update Health Check Logic
- **File**: `usr/local/phoenix_hypervisor/bin/managers/portainer-manager.sh`
- **Function**: `wait_for_system_ready`
- **Action**: The current health check for DNS is calling the `check_dns_resolution.sh` script without the required arguments. I will update the logic to iterate through a list of critical domains and call the health check script with the correct arguments for each.

### 2. Define Critical Domains
- **File**: `usr/local/phoenix_hypervisor/bin/managers/portainer-manager.sh`
- **Function**: `wait_for_system_ready`
- **Action**: I will define an associative array of critical domains and their expected IP addresses to be checked. This will include:
    - `portainer.internal.thinkheads.ai`
    - `traefik.internal.thinkheads.ai`
    - `step-ca.internal.thinkheads.ai`

### 3. Implement Robust Health Check
- **File**: `usr/local/phoenix_hypervisor/bin/managers/portainer-manager.sh`
- **Function**: `wait_for_system_ready`
- **Action**: The updated logic will loop through the defined domains and execute the `check_dns_resolution.sh` script with the `--context host`, `--domain`, and `--expected-ip` arguments. If any of the checks fail, the entire health check will fail, ensuring that the system does not proceed in a partially broken state.