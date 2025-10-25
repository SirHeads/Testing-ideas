# Network Data Flow Diagram Options

Here are four different structural options for the network data flow diagram, as requested.

## Option 1: Left-to-Right Flow

This option uses a left-to-right flow, which is a common convention for process diagrams.

```mermaid
graph LR
    subgraph External Network
        A[User/Client]
    end

    subgraph Proxmox Hypervisor
        subgraph Public-Facing Services
            B[Nginx Gateway - LXC 101]
        end

        subgraph Internal Services
            C[Traefik Mesh - LXC 102]
            D[Step-CA - LXC 103]
            E[LXC GPU Services]
            F[VM Docker Portainer]
            G[VM Docker Agents]
        end

        subgraph DNS
            H[Public DNS]
            I[Internal DNS]
        end
    end

    A -- HTTPS --> B;
    B -- routes to --> C;
    C -- routes to --> E;
    C -- routes to --> F;
    C -- routes to --> G;
    E -- communicates with --> D;
    F -- communicates with --> D;
    G -- communicates with --> D;
    B -- obtains/renews certs from --> L[Let's Encrypt];
    H -- resolves public domains --> A;
    I -- resolves internal domains --> C;
    I -- resolves internal domains --> E;
    I -- resolves internal domains --> F;
    I -- resolves internal domains --> G;
```

## Option 2: Top-to-Bottom Flow with Grouped Internal Services

This option uses a top-to-bottom flow and groups the internal services together for a more compact representation.

```mermaid
graph TD
    A[User/Client] --> B[Nginx Gateway - LXC 101];
    B --> C[Traefik Mesh - LXC 102];
    
    subgraph Internal Services
        direction LR
        D[Step-CA - LXC 103]
        E[LXC GPU Services]
        F[VM Docker Portainer]
        G[VM Docker Agents]
    end

    C --> E;
    C --> F;
    C --> G;
    E --> D;
    F --> D;
    G --> D;

    subgraph External Services
        L[Let's Encrypt]
    end

    B --> L;

    subgraph DNS
        direction LR
        H[Public DNS]
        I[Internal DNS]
    end

    A -- resolved by --> H;
    C -- resolved by --> I;
    E -- resolved by --> I;
    F -- resolved by --> I;
    G -- resolved by --> I;
```

## Option 3: Hub-and-Spoke Model

This option uses a hub-and-spoke model to emphasize the central role of the Traefik mesh in routing internal traffic.

```mermaid
graph TD
    subgraph "External"
        A[User/Client]
        L[Let's Encrypt]
        H[Public DNS]
    end

    subgraph "Gateway"
        B[Nginx Gateway - LXC 101]
    end

    subgraph "Service Mesh"
        C[Traefik Mesh - LXC 102]
    end

    subgraph "Internal Services"
        D[Step-CA - LXC 103]
        E[LXC GPU Services]
        F[VM Docker Portainer]
        G[VM Docker Agents]
        I[Internal DNS]
    end

    A -- HTTPS --> B;
    B -- routes to --> C;
    B -- obtains certs from --> L;
    A -- DNS lookup --> H;

    C --> E;
    C --> F;
    C --> G;
    
    E -- needs certs from --> D;
    F -- needs certs from --> D;
    G -- needs certs from --> D;

    E -- DNS lookup --> I;
    F -- DNS lookup --> I;
    G -- DNS lookup --> I;
```

## Option 4: Swimlane Diagram

This option uses a swimlane diagram to clearly delineate the different network zones and the services that reside within them.

```mermaid
graph TD
    subgraph External Zone
        A[User/Client]
        L[Let's Encrypt]
        H[Public DNS]
    end

    subgraph DMZ
        B[Nginx Gateway - LXC 101]
    end

    subgraph Internal Zone
        C[Traefik Mesh - LXC 102]
        D[Step-CA - LXC 103]
        E[LXC GPU Services]
        F[VM Docker Portainer]
        G[VM Docker Agents]
        I[Internal DNS]
    end

    A -- HTTPS --> B;
    B -- routes to --> C;
    B -- ACME Challenge --> L;
    A -- DNS Query --> H;

    C -- routes to --> E;
    C -- routes to --> F;
    C -- routes to --> G;

    E -- Certificate Request --> D;
    F -- Certificate Request --> D;
    G -- Certificate Request --> D;

    E -- DNS Query --> I;
    F -- DNS Query --> I;
    G -- DNS Query -- > I;
```

## Option 5: Vertical Swimlane Diagram

This option uses a vertical swimlane diagram to clearly delineate the different network zones and the services that reside within them.

```mermaid
graph TD
    subgraph External Zone
        A[User/Client]
        L[Let's Encrypt]
        H[Public DNS]
    end

    subgraph DMZ
        B[Nginx Gateway - LXC 101]
    end

    subgraph Internal Zone
        C[Traefik Mesh - LXC 102]
        D[Step-CA - LXC 103]
        E[LXC GPU Services]
        F[VM Docker Portainer]
        G[VM Docker Agents]
        I[Internal DNS]
    end

    A -- HTTPS --> B;
    B -- routes to --> C;
    B -- ACME Challenge --> L;
    A -- DNS Query --> H;

    C -- routes to --> E;
    C -- routes to --> F;
    C -- routes to --> G;

    E -- Certificate Request --> D;
    F -- Certificate Request --> D;
    G -- Certificate Request --> D;

    E -- DNS Query --> I;
    F -- DNS Query --> I;
    G -- DNS Query --> I;
```