# Firewall and Connectivity Audit Plan

## 1. Objective

To diagnose and confirm the root cause of the network connectivity failures between the Traefik container (LXC 102), the Step-CA container (LXC 103), and the Portainer VM (1001). The primary hypothesis is that Proxmox firewall rules are incorrectly blocking this traffic.

## 2. Audit Steps

This plan outlines a series of diagnostic commands to be executed to gather a complete picture of the firewall configuration and network state.

### Step 1: Inspect Proxmox Cluster Firewall Rules

We will dump the live firewall rules from the Proxmox host to verify that the rules defined in the JSON configuration have been correctly applied and that there are no conflicting rules.

*   **Command:** `cat /etc/pve/firewall/cluster.fw`

### Step 2: Inspect Firewall Settings for Each Guest

Each VM and container has its own firewall toggle in Proxmox. We need to verify that the firewall is enabled for the networking LXCs and the Portainer VM as intended.

*   **Commands:**
    *   `pct config 101 | grep firewall`
    *   `pct config 102 | grep firewall`
    *   `pct config 103 | grep firewall`
    *   `qm config 1001 | grep firewall`

### Step 3: Live Network Traffic Analysis

We will use `tcpdump` on the Proxmox host to monitor traffic on the `vmbr0` bridge. This will allow us to see in real-time if packets from Traefik (10.0.0.12) to Portainer (10.0.0.101) are being dropped.

*   **Command:** `tcpdump -i vmbr0 -n host 10.0.0.12 and host 10.0.0.101`
    *   *This command will be run in the background while we attempt to trigger the failing behavior.*

### Step 4: Re-run Failing Connectivity Test

While `tcpdump` is running, we will re-execute the `curl` command from within the Traefik container that previously timed out. The output of `tcpdump` will tell us if the packets are even reaching their destination or if they are being dropped by the host firewall.

*   **Command:** `pct exec 102 -- curl -v --cacert /ssl/phoenix_ca.crt https://portainer.internal.thinkheads.ai`

## 3. Expected Outcome

The output from these commands will provide a definitive answer to the following questions:

*   Are the correct firewall rules loaded on the Proxmox host?
*   Are the firewalls for the individual guests enabled as expected?
*   Are network packets from Traefik to Portainer being dropped, and if so, at what point?

This information will allow us to formulate a precise and effective remediation plan.
