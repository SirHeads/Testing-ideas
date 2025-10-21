# Network Traffic and DNS Resolution Flow Analysis

This document provides a visual analysis of the intended versus the actual network traffic and DNS resolution flows within the Phoenix Hypervisor environment. The diagrams highlight the critical DNS misconfigurations that are causing the system to fail.

## Intended Traffic Flow

This diagram illustrates the correct, intended flow of traffic and DNS resolution, as designed in the architecture.

```mermaid
graph TD
    subgraph "External Client"
        A[Client]
    end

    subgraph "Phoenix Hypervisor"
        subgraph "DNS Resolution"
            DNS[LXC 101: dnsmasq]
        end

        subgraph "Gateway Layer"
            B[LXC 101: Nginx Gateway]
        end

        subgraph "Internal Service Mesh"
            C[LXC 102: Traefik Proxy]
            D[LXC 103: Step-CA]
        end

        subgraph "Application Layer"
            E[VM 1001: Portainer]
        end
    end

    A -- "1. HTTPS to portainer.phoenix.thinkheads.ai" --> B
    B -- "2. DNS Query for ca.internal.thinkheads.ai" --> DNS
    DNS -- "3. Returns 10.0.0.10" --> B
    B -- "4. Validates Certs with Step-CA" --> D
    B -- "5. Proxies to traefik.internal.thinkheads.ai" --> C
    C -- "6. DNS Query for portainer.internal.thinkheads.ai" --> DNS
    DNS -- "7. Returns 10.0.0.101" --> C
    C -- "8. Proxies to Portainer" --> E

    style DNS fill:#cde4ff
```

## Actual (Broken) Traffic Flow

This diagram shows the actual, broken flow caused by the incorrect `/etc/hosts` entries in the setup scripts.

```mermaid
graph TD
    subgraph "External Client"
        A[Client]
    end

    subgraph "Phoenix Hypervisor"
        subgraph "DNS Resolution (Bypassed)"
            DNS[LXC 101: dnsmasq]
        end

        subgraph "Gateway Layer"
            B[LXC 101: Nginx Gateway]
        end

        subgraph "Internal Service Mesh"
            C[LXC 102: Traefik Proxy]
            D[LXC 103: Step-CA]
        end

        subgraph "Application Layer"
            E[VM 1001: Portainer]
        end
    end

    subgraph "Incorrect /etc/hosts Entries"
        C_HOSTS["/etc/hosts in LXC 102<br>10.0.0.101 portainer.internal.thinkheads.ai"]
        D_HOSTS["/etc/hosts in LXC 103<br>10.0.0.153 traefik.internal.thinkheads.ai"]
    end

    A -- "1. HTTPS to portainer.phoenix.thinkheads.ai" --> B
    B -- "2. Proxies to traefik.internal.thinkheads.ai" --> C
    C -- "3. ACME Challenge to ca.internal.thinkheads.ai" --> D
    D -- "4. Tries to validate challenge with traefik.internal.thinkheads.ai" --> B
    B -- "5. Fails to route challenge" --> D

    style C_HOSTS fill:#ffcccc
    style D_HOSTS fill:#ffcccc
```

## Analysis

The root cause of the failure is the static, incorrect `/etc/hosts` entries being injected into the Traefik and Step-CA containers. This misconfiguration completely bypasses the central `dnsmasq` server, leading to the following critical issues:

1.  **Step-CA (LXC 103) Failure:** The Step-CA container has a hardcoded entry pointing `traefik.internal.thinkheads.ai` to the Nginx gateway's IP (`10.0.0.153`). When Traefik attempts an ACME challenge, the Step-CA tries to validate the challenge by sending a request to the Nginx gateway instead of directly to Traefik. The Nginx gateway is not configured to handle these internal validation requests, causing the ACME challenge to fail.
2.  **Traefik (LXC 102) Failure:** The Traefik container has hardcoded entries for all backend services, pointing them to the wrong IP address. This prevents Traefik from discovering and routing traffic to the correct services.

The combination of these two failures creates a complete breakdown of the internal networking and certificate management systems. The system is unable to issue or validate certificates, and internal services are unreachable.