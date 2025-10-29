# Nginx Bootstrap Surgical Fix Plan

This document outlines the precise plan to fix the Nginx bootstrap failure by temporarily hardcoding the Step-CA IP address only where needed, while maintaining the final desired architecture of routing the CA service through Traefik.

### 1. Confirm Nginx Bootstrap Fix (Already Implemented)
- **File**: `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh`
- **Status**: **Complete**. The `step ca bootstrap` command has already been updated to use the hardcoded IP `10.0.0.10`. This change will be kept.

### 2. Restore Traefik Routing for Step-CA
- **File**: `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`
- **Action**: I will re-add the `traefik_service` definition to the Step-CA container (`103`). This ensures that after the initial bootstrap, all other services will correctly resolve `ca.internal.thinkheads.ai` to Traefik, as intended.

### 3. Restore Dynamic DNS Generation
- **File**: `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh`
- **Action**: I will remove the static DNS entry for `ca.internal.thinkheads.ai` again. The dynamic DNS generation logic will now correctly create the record pointing to Traefik based on the restored `traefik_service` definition.

### 4. Correct Health Check Expectation
- **File**: `usr/local/phoenix_hypervisor/bin/managers/portainer-manager.sh`
- **Action**: I will update the health check to expect the Traefik IP (`10.0.0.12`) for `ca.internal.thinkheads.ai`, aligning the health check with the final system architecture.

This surgical approach will resolve the bootstrap dependency issue while ensuring the system operates as designed once all components are online.