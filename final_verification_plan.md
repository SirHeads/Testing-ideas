# Final Verification Plan

This document outlines the steps to verify the fixes applied to the `phoenix-cli` scripts. The goal is to perform a clean, end-to-end synchronization of the system and then run a series of diagnostic commands to confirm that all components are healthy and correctly configured.

### Step 1: Execute a Clean System Synchronization

We will run the `phoenix sync all` command with the `--reset-portainer` flag. This will wipe the existing Portainer state and force the system to rebuild everything from the declarative configurations.

**Command:**
```bash
/usr/local/phoenix_hypervisor/bin/phoenix-cli sync all --reset-portainer
```

**Expected Outcome:**
*   The command should complete without any errors.
*   The logs should show that all certificates, including the client certificates, were generated successfully.
*   The logs should show that the Docker Swarm was initialized *before* the certificate renewals.
*   The logs should show that all Docker secrets were created successfully.
*   The logs should show that the Portainer and application stacks were deployed successfully.

### Step 2: Run System Health and Diagnostic Commands

After the `sync all` command completes, we will run the provided `get_system_status.sh` script to perform a comprehensive health check of the entire system.

**Command:**
```bash
./get_system_status.sh
```

**Expected Outcome:**
*   The script should run without errors.
*   All checks should report a "HEALTHY" or "OK" status.
*   Specifically, we will look for:
    *   Correct status for all LXC containers and VMs.
    *   Successful verification of all TLS certificates.
    *   A healthy Docker Swarm status with all nodes present and ready.
    *   Correctly running Portainer and application containers.
    *   Healthy Nginx and Traefik proxy configurations.

If both of these steps complete successfully, we can be confident that the underlying race condition and certificate generation bugs have been resolved.