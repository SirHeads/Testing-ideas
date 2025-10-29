# Nginx Bootstrap Fix Plan

This document outlines the plan to fix the Nginx container's bootstrap process by temporarily hardcoding the Step-CA container's IP address.

### 1. Hardcode Step-CA IP in Bootstrap Command
- **File**: `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh`
- **Action**: I will modify the `step ca bootstrap` command to use the `--ca-url` flag with the hardcoded IP address of the Step-CA container (`10.0.0.10`). This will allow the Nginx container to bypass the DNS resolution issue during its initial setup.

### 2. Revert Traefik Service Definition
- **File**: `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`
- **Container ID**: `103` (Step-CA)
- **Action**: I will remove the `traefik_service` definition from the Step-CA container's configuration. This will prevent the DNS generation script from creating a conflicting record.

### 3. Restore Static DNS Entry
- **File**: `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh`
- **Action**: I will re-introduce the static DNS entry for `ca.internal.thinkheads.ai`, pointing it directly to the Step-CA container's IP address (`10.0.0.10`). This will ensure that all other services can correctly resolve the CA's address.

### 4. Correct the Health Check
- **File**: `usr/local/phoenix_hypervisor/bin/managers/portainer-manager.sh`
- **Function**: `wait_for_system_ready`
- **Action**: The health check will be updated to expect the Step-CA container's direct IP address (`10.0.0.10`) for the `ca.internal.thinkheads.ai` hostname.

This plan will resolve the immediate bootstrap failure while maintaining the correct DNS configuration for the rest of the system.