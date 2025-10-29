# LXC Manager Health Check Fix Plan

This document outlines the plan to fix the `lxc-manager.sh` script to correctly use the declarative health checks defined in the `phoenix_lxc_configs.json` file.

### 1. Remove Hardcoded Health Check
- **File**: `usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh`
- **Function**: `run_health_check`
- **Action**: I will remove the entire `if [ "$CTID" -eq 101 ]` block. This hardcoded logic is preventing the declarative health check for the Nginx container from being used.

### 2. Unify Health Check Logic
- **File**: `usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh`
- **Function**: `run_health_check`
- **Action**: I will modify the generic health check logic to correctly parse and execute the health checks defined in the `health_checks` array in the JSON configuration. This will ensure that all health checks, including the one for Nginx, are handled in a consistent and declarative manner.