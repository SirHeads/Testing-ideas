# Component Overview

```mermaid
graph TD
    subgraph Hypervisor
        LXC101[LXC 101: Nginx Gateway]
        LXC102[LXC 102: Traefik]
        LXC103[LXC 103: Step-CA]
        VM1001[VM 1001: Portainer]
        VM1002[VM 1002: drphoenix]
    end

    subgraph Docker Swarm
        VM1001 --> Swarm_Manager
        VM1002 --> Swarm_Worker
    end

    subgraph Network Traffic
        Internet --> LXC101
        LXC101 --> LXC102
        LXC102 --> VM1001
        LXC102 --> VM1002
    end

    subgraph Certificate Authority
        LXC103 --> LXC101
        LXC103 --> LXC102
        LXC103 --> VM1001
        LXC103 --> VM1002
    end
