# Step-CA Traefik Integration Plan

This document outlines the plan to route the Step-CA service through the Traefik service mesh for a more unified and consistent architecture.

### 1. Add Traefik Service Definition
- **File**: `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`
- **Container ID**: `103` (Step-CA)
- **Action**: I will add a `traefik_service` definition to the Step-CA container's configuration. This will instruct the `generate_traefik_config.sh` script to create a routing rule for the service. The service will be named `ca` and will be routed to port `9000`.

### 2. Update the DNS Generation Script
- **File**: `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh`
- **Action**: The script currently has a hardcoded DNS entry for `ca.internal.thinkheads.ai`. I will remove this static entry, as the script's dynamic discovery logic will now automatically create the correct DNS record pointing to the Traefik IP (`10.0.0.12`).

### 3. Correct the Health Check
- **File**: `usr/local/phoenix_hypervisor/bin/managers/portainer-manager.sh`
- **Function**: `wait_for_system_ready`
- **Action**: The health check will be updated to reflect the new architecture:
    - The hostname will be changed from `step-ca.internal.thinkheads.ai` to `ca.internal.thinkheads.ai`.
    - The expected IP address will be changed to `10.0.0.12`, the IP of the Traefik container.

This plan will ensure that the Step-CA service is properly integrated into the service mesh, with DNS and health checks aligned to the new architecture.