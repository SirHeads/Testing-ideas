# Portainer Manager Timeout Fix

## Problem

The `phoenix sync all` command fails with a connection timeout when the `portainer-manager.sh` script attempts to create the initial admin user.

## Root Cause Analysis

A systematic investigation has confirmed the following:
1.  The Portainer service is correctly configured in its `docker-compose.yml` to publish port 9000.
2.  The Portainer Docker container is running successfully inside VM 1001.
3.  A process inside VM 1001 is actively listening on port 9000 on all network interfaces.
4.  The `curl` command from the hypervisor (10.0.0.13) to the Portainer VM (10.0.0.111) on port 9000 times out.

This definitively isolates the problem to the Proxmox firewall. The cluster-level firewall (`cluster.fw`) has a default `DROP` policy for incoming traffic. The connection is being dropped at the cluster level before it can be evaluated by the more permissive VM-level rules (`1001.fw`).

## Solution

The solution is to add a new global firewall rule that explicitly allows the hypervisor to connect to the Portainer VM on port 9000. This rule will be added to the `global_firewall_rules` array in the `phoenix_hypervisor_config.json` file, ensuring it is applied at the cluster level.

### Proposed Change

Add the following JSON object to the `shared_volumes.firewall.global_firewall_rules` array in `usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json`:

```json
{
    "type": "in",
    "action": "ACCEPT",
    "source": "10.0.0.13",
    "dest": "10.0.0.111",
    "proto": "tcp",
    "port": "9000",
    "comment": "Allow Proxmox host to access Portainer for initial setup"
}
```

This change is declarative, idempotent, and aligns with the existing design of the firewall management system. The next time `phoenix sync all` is run, the `hypervisor_feature_setup_firewall.sh` script will automatically read this new rule and apply it to the `cluster.fw` file, resolving the timeout issue.