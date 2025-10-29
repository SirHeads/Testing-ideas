# DNS Fix Plan v3

This document outlines the corrected plan to fix the DNS health check failure by updating the expected IP address in the `portainer-manager.sh` script.

### 1. Correct the Expected IP in the Health Check
- **File**: `usr/local/phoenix_hypervisor/bin/managers/portainer-manager.sh`
- **Function**: `wait_for_system_ready`
- **Action**: The `critical_domains` array incorrectly expects Traefik-routed services to resolve to `10.0.0.102`. This will be corrected to `10.0.0.12`, the actual IP address of the Traefik container that manages the internal service mesh. This will align the health check with the correct network architecture.