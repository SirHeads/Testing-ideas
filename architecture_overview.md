# Architecture Overview

- **LXC 103 (Step-CA):** The root of all trust in the system. It is responsible for issuing and managing all internal TLS certificates, ensuring secure communication between all components.

- **VM 1001 (Portainer):** The primary management interface for the Docker Swarm environment. It runs the Portainer server and is responsible for deploying and managing all Docker stacks.

- **VM 1002 (drphoenix):** The primary worker node in the Docker Swarm. It runs the Portainer agent and is responsible for executing the Docker containers that make up the ThinkTanks.AI services.

- **LXC 102 (Traefik):** The internal reverse proxy and load balancer. It is responsible for routing traffic to the appropriate services based on their DNS names and for providing automatic service discovery.

- **LXC 101 (Nginx):** The external-facing reverse proxy and gateway. It is responsible for terminating all external TLS connections and for routing traffic to the appropriate internal services.
