# Firewall and Network Trace Plan

**Objective:** Diagnose the persistent connection issue between Traefik (LXC 102) and the Docker Swarm manager (VM 1001) by capturing and analyzing network traffic.

This plan will use `tcpdump` to monitor the packets flowing between the two components, which will give us a definitive answer as to why the connection is failing.

## Plan

1.  **Install `tcpdump` on the Proxmox Host**:
    *   The `tcpdump` utility is required to capture the network traffic.

2.  **Start the Network Capture**:
    *   We will start `tcpdump` on the Proxmox host, filtering for traffic between the IP addresses of the Traefik container (`10.0.0.12`) and the Docker Swarm manager (`10.0.0.111`) on port `2375`.

3.  **Restart the Traefik Service**:
    *   While the capture is running, we will restart the Traefik service in LXC 102. This will trigger a new connection attempt.

4.  **Stop the Capture and Analyze the Results**:
    *   We will stop the `tcpdump` capture and examine the output file. The results will show us one of three things:
        *   **No packets:** This would indicate a routing or firewall issue at the Proxmox level.
        *   **SYN packets with no reply:** This would point to a firewall on the Docker host (VM 1001) that is blocking the connection.
        *   **A full TCP handshake:** This would indicate that the problem is at the application layer, within the Traefik binary itself.

This plan will provide the final piece of evidence needed to solve this problem.
