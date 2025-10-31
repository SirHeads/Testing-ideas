# Phoenix Server Component Roles

## 1. Introduction

This document outlines the purpose and role of each LXC container and virtual machine created by the `phoenix create` command. Understanding the function of each component is crucial for managing and troubleshooting the Phoenix server infrastructure.

## 2. LXC Containers

### 900 - Copy-Base
-   **Purpose**: Base template for LXC containers.
-   **Description**: A minimal Ubuntu 24.04 installation with basic configurations. It serves as the foundation from which other, more specialized containers are cloned, ensuring consistency and rapid provisioning.

### 103 - Step-CA
-   **Purpose**: Internal Certificate Authority (CA).
-   **Description**: Runs the Smallstep CA service. It is the core of the internal Public Key Infrastructure (PKI), responsible for issuing and managing TLS certificates for all internal services, enabling secure, encrypted communication across the platform.

### 101 - Nginx-Phoenix
-   **Purpose**: API Gateway.
-   **Description**: This container runs Nginx and acts as the primary entry point for external traffic. It proxies requests to the appropriate internal services and secures its own communication using certificates obtained from the Step-CA (103).

### 102 - Traefik-Internal
-   **Purpose**: Internal Service Mesh and Reverse Proxy.
-   **Description**: Runs Traefik to manage internal service-to-service communication, service discovery, and load balancing. It integrates with the Step-CA to automatically provision TLS certificates for the internal services it routes traffic to.

## 3. Virtual Machines

### 9000 - ubuntu-2404-cloud-template
-   **Purpose**: Base template for virtual machines.
-   **Description**: A pre-configured Ubuntu 24.04 cloud image that serves as the base for creating new virtual machines, ensuring a consistent and secure starting point.

### 1001 - Portainer
-   **Purpose**: Container Management Control Plane.
-   **Description**: Hosts the primary Portainer instance. Portainer provides a graphical user interface to manage all Docker environments within the Phoenix infrastructure, including the Docker host running on VM 1002.

### 1002 - drphoenix
-   **Purpose**: Application Workload Host.
-   **Description**: This VM is a dedicated Docker host managed by the Portainer instance (1001). It is responsible for running the core application services, including the Qdrant vector database and the main ThinkHeads AI application.