# System Architecture & Network Flow

This diagram illustrates the high-level architecture of the Phoenix Hypervisor system and the flow of network traffic from the public internet to the backend services.

```mermaid
graph TD
    subgraph "Proxmox Host (10.0.0.13)"
        direction LR
        subgraph "VMs"
            VM1001[VM 1001: Portainer Server <br> 10.0.0.111]
            VM1002[VM 1002: drphoenix <br> 10.0.0.102]
        end
        subgraph "LXCs"
            LXC103[LXC 103: Step-CA <br> 10.0.0.10]
            LXC102[LXC 102: Traefik <br> 10.0.0.12]
            LXC101[LXC 101: Nginx Gateway <br> 10.0.0.153]
        end
        subgraph "Host Services"
            DNS[dnsmasq]
            Firewall[pve-firewall]
            NFS[NFS Server]
        end
    end

    subgraph "External Network"
        Internet[Public Internet]
    end

    subgraph "Internal Services on VM 1002"
        ServiceA[Docker Stack A]
        ServiceB[Docker Stack B]
    end

    Internet -- "HTTPS/443" --> LXC101
    LXC101 -- "HTTP/80 (Proxy)" --> LXC102
    LXC102 -- "Routes Traffic Based on Hostname" --> ServiceA
    LXC102 -- "Routes Traffic Based on Hostname" --> ServiceB
    LXC102 -- "Routes Traffic to Portainer" --> VM1001

    VM1001 -- "Manages Docker Stacks" --> VM1002
    
    LXC101 -- "Requests Certs" --> LXC103
    LXC102 -- "Requests Certs" --> LXC103
    VM1001 -- "Requests Certs" --> LXC103
    VM1002 -- "Requests Certs" --> LXC103

    VM1001 -- "DNS Queries" --> DNS
    VM1002 -- "DNS Queries" --> DNS
    LXC101 -- "DNS Queries" --> DNS
    LXC102 -- "DNS Queries" --> DNS
    LXC103 -- "DNS Queries" --> DNS

    VM1001 -- "Mounts Volumes" --> NFS
    VM1002 -- "Mounts Volumes" --> NFS
    LXC101 -- "Mounts Volumes" --> NFS
    LXC102 -- "Mounts Volumes" --> NFS
    LXC103 -- "Mounts Volumes" --> NFS

    style VM1001 fill:#f9f,stroke:#333,stroke-width:2px
    style VM1002 fill:#f9f,stroke:#333,stroke-width:2px
    style LXC101 fill:#ccf,stroke:#333,stroke-width:2px
    style LXC102 fill:#ccf,stroke:#333,stroke-width:2px
    style LXC103 fill:#ccf,stroke:#333,stroke-width:2px
```
