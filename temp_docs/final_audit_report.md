# Live Network Diagnostics Plan

## 1. Objective

To definitively prove, through live network traffic analysis, that the Proxmox host firewall is the root cause of the connectivity failures between the core networking services.

## 2. Diagnostic Steps

This plan will use `tcpdump` to monitor network traffic in real-time, allowing us to observe the behavior of packets as they traverse the virtual network.

### Step 1: Start Packet Capture on the Proxmox Host

We will start a `tcpdump` process on the Proxmox host, specifically listening for traffic between the Traefik container (10.0.0.12) and the Portainer VM (10.0.0.101). This will run in the background and capture all packets related to our test.

*   **Command:** `tcpdump -i vmbr0 -n host 10.0.0.12 and host 10.0.0.101`

### Step 2: Trigger the Failing Network Request

While the packet capture is running, we will re-execute the `curl` command from within the Traefik container that has been consistently failing.

*   **Command:** `pct exec 102 -- curl -v --cacert /ssl/phoenix_ca.crt https://portainer.internal.thinkheads.ai`

### Step 3: Analyze the Packet Capture

The output of `tcpdump` will provide the definitive evidence we need. We will be looking for one of two outcomes:

1.  **No packets are seen:** This would indicate a routing issue *before* the firewall, which is highly unlikely given our previous findings.
2.  **Only outbound packets are seen:** This is the expected outcome. We should see SYN packets from Traefik (10.0.0.12) trying to initiate a connection, but no corresponding SYN-ACK packets from Portainer (10.0.0.101). This will prove that the firewall is dropping the incoming packets and is the root cause of the failure.

## 3. Next Steps

The results of this live diagnostic will provide the final piece of evidence. Once we have confirmed the firewall is the issue, we can proceed with confidence to correct the `phoenix_hypervisor_config.json` file.
