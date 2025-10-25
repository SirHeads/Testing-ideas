# Phoenix Hypervisor: Detailed Networking Architecture

## 1. Introduction

The Phoenix Hypervisor's networking architecture is a sophisticated, multi-layered system designed for security, scalability, and ease of management. It seamlessly integrates internal and external services, providing a robust foundation for a wide range of AI/ML/DL workloads. This document provides a detailed overview of the networking architecture, with a focus on the interplay between its core components.

## 2. Core Networking Components

The networking architecture is composed of the following core components:

*   **Dual-Horizon DNS**: The system utilizes a dual-horizon DNS setup, with a public-facing DNS for external services and a private, internal DNS for service-to-service communication. This provides a clear separation between public and private traffic, enhancing security and simplifying network management.
*   **Nginx Gateway (LXC 101)**: This is a dedicated LXC container that runs Nginx and acts as a reverse proxy for all external traffic. It is the single point of entry for all public-facing services, and it provides SSL termination, load balancing, and request routing.
*   **Traefik Mesh (LXC 102)**: This is a dedicated LXC container that runs Traefik and provides a service mesh for all internal services. It is responsible for routing traffic between services, and it also provides service discovery, load balancing, and circuit breaking.
*   **Step-CA (LXC 103)**: This is a dedicated LXC container that runs Step-CA and provides a private certificate authority for the entire system. It is used to issue SSL certificates for all the internal services, ensuring that all communication is encrypted.
*   **ACME Certificates**: The Nginx gateway is configured to automatically obtain and renew SSL certificates from Let's Encrypt using the ACME protocol. This ensures that all public-facing services are secured with a valid, trusted SSL certificate.
*   **LXC GPU Services**: These are specialized LXC containers that are configured with GPU passthrough, allowing them to run GPU-accelerated workloads such as machine learning and data processing.
*   **VM Docker Portainer**: This is a dedicated VM that runs Portainer, a centralized container management platform. It is used to manage all the Docker containers running on the hypervisor, and it provides a user-friendly interface for deploying, monitoring, and managing containerized applications.
*   **VM Docker Agents**: These are dedicated VMs that run the Portainer agent, allowing them to be managed by the central Portainer instance. They are used to run a variety of containerized workloads, including AI/ML/DL models and other services.

## 3. Detailed Network Data Flow

The following diagram illustrates the detailed network data flow for the Phoenix Hypervisor, highlighting the interactions between the various components:

```mermaid
graph TD
    subgraph External Network
        A[User/Client]
    end

    subgraph Proxmox Hypervisor
        subgraph Public-Facing Services
            B[Nginx Gateway (LXC 101)]
        end

        subgraph Internal Services
            C[Traefik Mesh (LXC 102)]
            D[Step-CA (LXC 103)]
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

## 4. Conclusion

The Phoenix Hypervisor's detailed networking architecture is a testament to its robust and scalable design. By leveraging a combination of best-in-class open-source technologies, it provides a secure, resilient, and highly automated platform for managing complex virtualized environments. The clear separation of concerns between the various components, combined with the power of declarative configuration, makes it an ideal solution for a wide range of AI/ML/DL workloads.