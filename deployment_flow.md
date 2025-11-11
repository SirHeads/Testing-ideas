# Phoenix Hypervisor End-to-End Workflow

This document outlines the complete workflow for provisioning the hypervisor, creating guests, synchronizing the core infrastructure, and deploying applications using the `phoenix-cli`.

```mermaid
graph TD
    subgraph "Phase 1: Hypervisor Setup"
        A["phoenix setup"] --> B["hypervisor-manager.sh"];
        B --> C["Installs OS packages, configures ZFS, NFS, VFIO, NVIDIA drivers"];
    end

    subgraph "Phase 2: Guest Creation"
        D["phoenix create all"] --> E["phoenix-cli resolves dependency graph"];
        E --> F{"For each guest..."};
        F -- "LXC" --> G["lxc-manager.sh"];
        F -- "VM" --> H["vm-manager.sh"];
        G --> I["Creates/Clones LXC, applies base config, installs features [e.g., step-ca, traefik]"];
        H --> J["Clones VM, applies base config, installs features [e.g., docker]"];
        I --> K["Guests are running but not fully configured"];
        J --> K;
    end

    subgraph "Phase 3: Infrastructure Sync & Swarm Formation"
        L["phoenix sync all"] --> M["portainer-manager.sh"];
        M --> N["Syncs stack files to NFS"];
        N --> O["Runs certificate-renewal-manager"];
        O --> P["Initializes Swarm on VM 1001"];
        P --> Q["Joins VM 1002 to Swarm"];
        Q --> R["Deploys Portainer stack via swarm-manager"];
        R --> S["Generates & pushes Traefik config to LXC 102"];
        S --> T["Generates & pushes Nginx config to LXC 101"];
    end

    subgraph "Phase 4: Application Deployment"
        U["phoenix swarm deploy <app>"] --> V["swarm-manager.sh"];
        V --> W["Executes 'docker stack deploy' on Swarm Manager [VM 1001]"];
        W --> X["Swarm schedules services on Worker Node [VM 1002]"];
    end

    C --> D;
    K --> L;
    T --> U;