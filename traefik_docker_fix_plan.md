# Traefik Docker Swarm Integration Fix Plan

**Objective:** Resolve the `field not found, node: apiVersion` error in Traefik (LXC 102) and ensure it correctly integrates with the Docker Swarm provider.

The error indicates that the Traefik static configuration is likely formatted for a Kubernetes environment, not Docker. The fix involves correcting the configuration to use the Docker Swarm provider.

## Plan

1.  **Examine the Traefik Configuration Template**:
    *   Read the contents of `usr/local/phoenix_hypervisor/etc/traefik/traefik.yml.template` to confirm the incorrect configuration.

2.  **Correct the Traefik Configuration**:
    *   Modify the template to remove the Kubernetes-specific sections (`entryPoints`, `providers.kubernetesCRD`, etc.).
    *   Add the correct configuration for the Docker Swarm provider, including the endpoint and network settings.

3.  **Apply the Fix**:
    *   Run the `phoenix sync all` command again. This will:
        *   Push the corrected `traefik.yml` to LXC 102.
        *   Restart the Traefik service with the correct configuration.

4.  **Verify the Fix**:
    *   Check the Traefik logs in LXC 102 to confirm that the error is gone and that it is now correctly discovering services from the Docker Swarm.

This plan will ensure that Traefik is properly configured to work within the Phoenix Docker Swarm environment.
