# Step-CA Certificate Fix Plan

This document outlines the plan to fix the Step-CA's TLS certificate to include its own IP address, which will resolve the "certificate is valid for 127.0.0.1, not 10.0.0.10" error.

### 1. Update Step-CA Initialization
- **File**: `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_103.sh`
- **Action**: I will modify the `step ca init` command to include the Step-CA container's IP address (`10.0.0.10`) in the `--dns` flag. This will ensure that the CA's own TLS certificate is valid for both `localhost` and its container IP, allowing the Nginx container to establish a secure connection during the bootstrap process.