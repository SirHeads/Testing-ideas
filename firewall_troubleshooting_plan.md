# Final Firewall Fix Plan

## 1. Root Cause Confirmation

The output of `pve-firewall compile` has confirmed that there are no `iptables` rules in the `veth102i0-IN` chain that allow ICMP traffic. With a default `DROP` policy, this is the definitive cause of the network isolation of LXC 102.

## 2. The Permanent Fix

We will now apply a targeted, permanent fix by adding a rule to the LXC 102 firewall configuration that explicitly allows ICMP traffic from the internal network.

### Step 1: Add Permanent ICMP Rule

The following change needs to be made to `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json` to add the ICMP rule to the firewall configuration for LXC 102.

```json
{
    "type": "in",
    "action": "ACCEPT",
    "proto": "icmp",
    "source": "10.0.0.0/24",
    "comment": "Allow ICMP from internal network"
}
```

### Step 2: Fix the SSL Certificate Mismatch

The following change needs to be made to `usr/local/phoenix_hypervisor/etc/certificate-manifest.json` to add the IP address of the Swarm manager as a SAN to its certificate.

```json
"sans": [
    "portainer.internal.thinkheads.ai",
    "10.0.0.111",
    "localhost"
]
```

## 3. Implementation Plan

To apply these changes, I will need to switch to "Code" mode. Once the changes are applied, we will re-run the `phoenix sync all` command to confirm that the entire process now completes successfully.