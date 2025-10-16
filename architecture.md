graph TD
    subgraph "Proxmox Host"
        subgraph "VM 1001 - Portainer Server"
            Portainer_Server[Portainer UI/API]
        end

        subgraph "VM 1002 - Portainer Agent"
            Portainer_Agent[Portainer Agent]
            Docker_Stacks[Docker Stacks: qdrant_service, thinkheads_ai_app]
            Portainer_Agent -- Manages --> Docker_Stacks
        end

        subgraph "LXC Containers"
            LXC_101[101: Nginx-Phoenix - Reverse Proxy/DNS]
            LXC_102[102: Traefik-Internal - Service Mesh]
            LXC_103[103: Step-CA - Certificate Authority]
        end
    end

    subgraph "External Network"
        User[User/Admin]
    end

    User -- HTTPS --> LXC_101
    LXC_101 -- Routes Traffic --> Portainer_Server
    LXC_101 -- Routes Traffic --> LXC_102
    LXC_102 -- Routes Internal Traffic --> Docker_Stacks
    Portainer_Server -- Controls --> Portainer_Agent
    LXC_102 -- Uses Certs From --> LXC_103
    Portainer_Server -- Uses Certs From --> LXC_103