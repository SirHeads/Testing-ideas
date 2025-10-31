# Phoenix Setup Command Summary

## 1. Overview

The `phoenix setup` command is the foundational command of the Phoenix Hypervisor orchestration system. It is responsible for preparing the Proxmox hypervisor for the creation and management of virtualized resources. This command is designed to be idempotent, and it can be run multiple times without causing any issues.

## 2. Workflow

The `setup` workflow is a comprehensive process that configures all the necessary components of the hypervisor. The following is a high-level overview of the steps involved:

1.  **Parse Command**: The `phoenix-cli` script parses the `setup` command and its arguments.
2.  **Dispatch to Manager**: The `phoenix-cli` script dispatches the setup task to the `hypervisor-manager.sh` script.
3.  **Execute Setup Workflow**: The `hypervisor-manager.sh` script executes the setup workflow, which includes the following steps:
    *   **Initial System Configuration**: The script performs a series of initial system configurations, including updating the package repositories, installing necessary packages, and configuring the system's locale and time zone.
    *   **ZFS Configuration**: The script configures the ZFS storage pools, including creating the necessary datasets and setting the appropriate properties.
    *   **Network Configuration**: The script configures the network interfaces, including the Proxmox bridge and the DNS server.
    *   **Firewall Configuration**: The script configures the firewall, including creating the necessary rules and security groups.
    *   **NFS Configuration**: The script configures the NFS server, including creating the necessary exports and setting the appropriate permissions.
    *   **AppArmor Configuration**: The script configures AppArmor, including loading the necessary profiles and setting the appropriate security policies.
    *   **NVIDIA GPU Configuration**: The script configures the NVIDIA GPUs, including installing the necessary drivers and configuring GPU passthrough.
    *   **User and Group Configuration**: The script creates the necessary users and groups, and it sets the appropriate permissions.

## 3. Command Sequence Diagram

```mermaid
sequenceDiagram
    actor User
    participant phoenix_cli as phoenix-cli
    participant hypervisor_manager as hypervisor-manager.sh
    participant Proxmox

    User->>phoenix_cli: execute `phoenix setup`
    phoenix_cli->>hypervisor_manager: dispatch `setup`
    hypervisor_manager->>Proxmox: Perform initial system configuration
    hypervisor_manager->>Proxmox: Configure ZFS storage pools
    hypervisor_manager->>Proxmox: Configure network interfaces
    hypervisor_manager->>Proxmox: Configure firewall
    hypervisor_manager->>Proxmox: Configure NFS server
    hypervisor_manager->>Proxmox: Configure AppArmor
    hypervisor_manager->>Proxmox: Configure NVIDIA GPUs
    hypervisor_manager->>Proxmox: Configure users and groups