# Nginx Health Check Fix Plan

This document outlines the plan to fix the Nginx health check to be independent of Traefik, ensuring it correctly validates the bootstrap conditions.

### 1. Correct the Nginx Health Check's Expected IP
- **File**: `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`
- **Container ID**: `101` (Nginx)
- **Action**: The specialized health check for the Nginx container will be updated to expect the Step-CA's direct IP address (`10.0.0.10`). This ensures that the health check is validating the actual connection that's required for the Nginx bootstrap process, making the check independent of Traefik's status.